"""Owner operational alerts (the "Urgent" alert table), emailed to ERROR_ALERT_EMAIL.

Each method is called where the event happens; it counts the event and, when the trigger is met,
sends one named alert through ``ErrorAlerts`` (plain text, counts and codes only, throttled).

Alert (doc section): trigger used here
* Sign-up OTP emails not arriving (2. Authentication): any code-email send failure; or, over the
  last hour, >= 10 code checks with < 50% correct.
* Google/Apple sign-in failing (2. Authentication): > 10% failed over 15 min (>= 10 attempts).
* AI credits or quota low / exhausted (6. Rin AI): 80% and 95% of AI_ACCOUNT_MONTHLY_BUDGET_INR;
  any 429 / 402 / insufficient-quota / rejected key from OpenAI.
* Rin AI down or very slow (6. Rin AI): > 25% of replies failed, or median reply > 30 s, over
  15 min (>= 5 replies).
* User paid but didn't get STAR (8. Subscriptions): a verified purchase without STAR, or the health
  check finds an active subscription on a standard user.
* Payment or receipt validation failing (8. Subscriptions): store verification errors, webhook
  failures, reconcile job failure.
* Report PDF generation failing or timing out (7. Profile): a report job failed, AI insights
  failed, or jobs are stuck in the queue.
* Streak or day-rollover job failed (7. Profile): day jobs (reminders, day-ending-soon) failed or
  missed their schedule; timezone errors.

Bounce spikes need the email provider's bounce webhook; plain SMTP cannot see bounces, so that
part of the OTP alert waits for the production email provider (docs/pending-tasks.md).

Rates are counted per process in memory (the API runs without Redis), so with several API
processes each one judges its own traffic. Thresholds are constants below.
"""

from __future__ import annotations

import statistics
import time
from collections import deque
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from app.integrations.error_alerts import ErrorAlerts, Fact

# --- thresholds (owner table; change here)
OTP_WINDOW_S = 3600
OTP_MIN_CHECKS = 10
OTP_MIN_SUCCESS = 0.5
OAUTH_WINDOW_S = 15 * 60
OAUTH_MIN_ATTEMPTS = 10
OAUTH_MAX_FAILURE = 0.10
RIN_WINDOW_S = 15 * 60
RIN_MIN_REPLIES = 5
RIN_MAX_FAILURE = 0.25
RIN_SLOW_MEDIAN_S = 30.0
AI_BUDGET_LEVELS = (95, 80)  # highest first
AI_BUDGET_REPEAT_S = 24 * 3600
HTTP_PAYMENT_REQUIRED = 402
HTTP_TOO_MANY_REQUESTS = 429


class Alert(StrEnum):
    OTP_EMAIL = "otp_email"
    OAUTH = "oauth"
    AI_QUOTA = "ai_quota"
    RIN_HEALTH = "rin_health"
    PAID_NO_STAR = "paid_no_star"
    PAYMENT_VALIDATION = "payment_validation"
    REPORTS = "reports"
    DAY_JOBS = "day_jobs"


@dataclass(frozen=True, slots=True)
class _Spec:
    section: str
    title: str
    action: str


SPECS: dict[Alert, _Spec] = {
    Alert.OTP_EMAIL: _Spec(
        "2. Authentication",
        "Sign-up OTP emails not arriving",
        "Check the SMTP provider (login, sending limits, domain) and send a test sign-up.",
    ),
    Alert.OAUTH: _Spec(
        "2. Authentication",
        "Google/Apple sign-in failing",
        "Check the Google/Apple client ids in .env, the provider status pages and server logs.",
    ),
    Alert.AI_QUOTA: _Spec(
        "6. Rin AI",
        "Vendor-side AI credits or quota low or exhausted",
        "Add credits or raise the limit at platform.openai.com (Billing and Limits). Rin runs in "
        "basic mode until then.",
    ),
    Alert.RIN_HEALTH: _Spec(
        "6. Rin AI",
        "Rin AI down or very slow",
        "Check status.openai.com and the server logs (rin_model_failed). Rin answers in basic "
        "mode meanwhile.",
    ),
    Alert.PAID_NO_STAR: _Spec(
        "8. Subscriptions",
        "User paid but didn't get STAR",
        "Check the store product ids (billing.store_product) and the subscription rows; grant "
        "STAR by support if needed.",
    ),
    Alert.PAYMENT_VALIDATION: _Spec(
        "8. Subscriptions",
        "Payment or receipt validation failing",
        "Check the Play service account / App Store keys in .env and the store status pages.",
    ),
    Alert.REPORTS: _Spec(
        "7. Profile",
        "Report PDF generation failing or timing out",
        "Check that the worker is running and the server logs (report_failed, "
        "report_insights_failed).",
    ),
    Alert.DAY_JOBS: _Spec(
        "7. Profile",
        "Streak or day-rollover job failed",
        "Check that the worker and scheduler are running, and the timezone data on the server.",
    ),
}


class RateWindow:
    """Outcomes (and optional durations) over a sliding time window."""

    def __init__(self, window_s: float, clock: Callable[[], float]) -> None:
        self._window = window_s
        self._clock = clock
        self._events: deque[tuple[float, bool, float | None]] = deque()

    def add(self, ok: bool, seconds: float | None = None) -> None:
        self._events.append((self._clock(), ok, seconds))
        self._trim()

    def _trim(self) -> None:
        edge = self._clock() - self._window
        while self._events and self._events[0][0] < edge:
            self._events.popleft()

    def stats(self) -> tuple[int, int, float | None]:
        """(events, failures, median duration of the timed events)."""
        self._trim()
        failures = sum(1 for _, ok, _ in self._events if not ok)
        times = [s for _, _, s in self._events if s is not None]
        return len(self._events), failures, statistics.median(times) if times else None


class OpsMonitor:
    def __init__(
        self, alerts: ErrorAlerts | None, *, clock: Callable[[], float] = time.monotonic
    ) -> None:
        self._alerts = alerts
        self._otp = RateWindow(OTP_WINDOW_S, clock)
        self._oauth = RateWindow(OAUTH_WINDOW_S, clock)
        self._rin = RateWindow(RIN_WINDOW_S, clock)

    def fire(
        self,
        alert: Alert,
        trigger: str,
        facts: Mapping[str, Fact] | None = None,
        *,
        key: str = "",
        repeat_s: float | None = None,
        exc: BaseException | None = None,
    ) -> None:
        if self._alerts is None:
            return
        spec = SPECS[alert]
        extra: dict[str, Any] = {} if repeat_s is None else {"repeat_s": repeat_s}
        self._alerts.alert(
            code=alert.value,
            section=spec.section,
            title=spec.title,
            trigger=trigger,
            facts=dict(facts or {}),
            action=spec.action,
            key=key,
            exc=exc,
            **extra,
        )

    # ------------------------------------------------------------ 2. Authentication
    def email_sent(self, template: str, *, ok: bool, error_type: str | None = None) -> None:
        if not ok:
            self.fire(
                Alert.OTP_EMAIL,
                "Email provider error while sending a code email",
                {"Template": template, "Error type": error_type or "-"},
                key=error_type or "",
            )

    def otp_checked(self, *, ok: bool) -> None:
        self._otp.add(ok)
        total, failures, _ = self._otp.stats()
        if total >= OTP_MIN_CHECKS and (total - failures) / total < OTP_MIN_SUCCESS:
            self.fire(
                Alert.OTP_EMAIL,
                "OTP verify success rate dropped sharply (codes may not be arriving)",
                {
                    "Checks (1h)": total,
                    "Correct": total - failures,
                    "Success": f"{(total - failures) * 100 // total}%",
                },
            )

    def oauth_checked(self, provider: str, *, ok: bool) -> None:
        self._oauth.add(ok)
        total, failures, _ = self._oauth.stats()
        if total >= OAUTH_MIN_ATTEMPTS and failures / total > OAUTH_MAX_FAILURE:
            self.fire(
                Alert.OAUTH,
                "Google/Apple sign-in failure rate above 10% over 15 minutes",
                {
                    "Attempts": total,
                    "Failed": failures,
                    "Failure": f"{failures * 100 // total}%",
                    "Last failed": provider if not ok else "-",
                },
            )

    # ------------------------------------------------------------ 6. Rin AI
    def ai_error(self, *, where: str, kind: str, status: int | None) -> None:
        """An OpenAI error. ``kind`` is rin_model.failure_kind (quota / account / retry)."""
        if kind in {"quota", "account"} or status in {
            HTTP_PAYMENT_REQUIRED,
            HTTP_TOO_MANY_REQUESTS,
        }:
            reason = {
                "quota": "insufficient quota / no credits",
                "account": "API key rejected",
            }.get(kind, f"HTTP {status}")
            self.fire(
                Alert.AI_QUOTA,
                f"OpenAI refused a call: {reason}",
                {"Where": where, "Kind": kind, "HTTP status": status or "-"},
                key=f"{kind}:{status}",
            )

    def ai_budget(self, *, spent_micro_inr: int, budget_micro_inr: int) -> None:
        if budget_micro_inr <= 0:
            return
        pct = spent_micro_inr * 100 / budget_micro_inr
        for level in AI_BUDGET_LEVELS:
            if pct >= level:
                self.fire(
                    Alert.AI_QUOTA,
                    f"AI spend this month reached {level}% of the budget",
                    {
                        "Spent (INR)": f"{spent_micro_inr / 1_000_000:.2f}",
                        "Budget (INR)": f"{budget_micro_inr / 1_000_000:.2f}",
                        "Used": f"{pct:.1f}%",
                    },
                    key=f"budget{level}",
                    repeat_s=AI_BUDGET_REPEAT_S,
                )
                return

    def rin_reply(self, *, ok: bool, seconds: float) -> None:
        self._rin.add(ok, seconds if ok else None)
        total, failures, median = self._rin.stats()
        if total < RIN_MIN_REPLIES:
            return
        if failures / total > RIN_MAX_FAILURE:
            self.fire(
                Alert.RIN_HEALTH,
                "Rin AI error rate above 25% over 15 minutes",
                {"Replies": total, "Failed": failures},
                key="errors",
            )
        elif median is not None and median > RIN_SLOW_MEDIAN_S:
            self.fire(
                Alert.RIN_HEALTH,
                "Rin AI median reply time above 30 seconds over 15 minutes",
                {"Replies": total, "Median": f"{median:.1f} s"},
                key="slow",
            )

    # ------------------------------------------------------------ 8. Subscriptions
    def payment_error(self, *, where: str, error_type: str) -> None:
        self.fire(
            Alert.PAYMENT_VALIDATION,
            "Store validation or payment webhook failed",
            {"Where": where, "Error type": error_type},
            key=f"{where}:{error_type}",
        )

    def paid_without_star(self, *, where: str, count: int = 1) -> None:
        self.fire(
            Alert.PAID_NO_STAR,
            "Store purchase succeeded but the user is not STAR",
            {"Where": where, "Users affected": count},
            key=where,
        )

    # ------------------------------------------------------------ 7. Profile
    def report_problem(
        self, trigger: str, facts: Mapping[str, Fact], *, key: str, exc: BaseException | None = None
    ) -> None:
        self.fire(Alert.REPORTS, trigger, facts, key=key, exc=exc)

    def day_job_problem(
        self, trigger: str, facts: Mapping[str, Fact], *, key: str, exc: BaseException | None = None
    ) -> None:
        self.fire(Alert.DAY_JOBS, trigger, facts, key=key, exc=exc)

    # ------------------------------------------------------------ worker health check
    def health(self, row: Mapping[str, Any], *, ai_budget_micro_inr: int | None) -> None:
        """Numbers from ops.fn_ops_health (worker, every 5 minutes)."""
        if row.get("reports_stuck"):
            self.report_problem(
                "Report jobs are stuck in the queue (timing out)",
                {"Stuck jobs": int(row["reports_stuck"])},
                key="stuck",
            )
        if row.get("reports_failed_1h"):
            self.report_problem(
                "Report jobs failed in the last hour",
                {"Failed (1h)": int(row["reports_failed_1h"])},
                key="failed",
            )
        if row.get("store_notifications_failed_1h"):
            self.payment_error(
                where="store webhooks (last hour)",
                error_type=f"{int(row['store_notifications_failed_1h'])} failed",
            )
        if row.get("paid_without_star"):
            self.paid_without_star(where="health check", count=int(row["paid_without_star"]))
        if ai_budget_micro_inr:
            self.ai_budget(
                spent_micro_inr=int(row.get("ai_spend_month_micro_inr") or 0),
                budget_micro_inr=ai_budget_micro_inr,
            )


NO_MONITOR = OpsMonitor(None)


class MonitoredEmail:
    """Wraps the email sender: a failed send raises the OTP-email alert, then re-raises."""

    def __init__(self, inner: Any, monitor: OpsMonitor) -> None:
        self._inner = inner
        self._monitor = monitor

    async def send(self, to: str, template: str, values: Mapping[str, str]) -> None:
        try:
            await self._inner.send(to, template, values)
        except Exception as exc:
            self._monitor.email_sent(template, ok=False, error_type=type(exc).__name__)
            raise

    async def send_plain(
        self, to: str, subject: str, body: str, *, reply_to: str | None = None
    ) -> None:
        await self._inner.send_plain(to, subject, body, reply_to=reply_to)
