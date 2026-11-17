"""Owner alert emails to ERROR_ALERT_EMAIL: crashes (unhandled API errors, failed jobs) and the
named operational alerts of ``ops_monitor`` (OTP email, sign-in, Rin, AI credits, payments,
reports, day jobs).

* Plain text only (``PlainEmailSender.send_plain``): no HTML part, nothing can render as markup.
* No user data: emails carry the environment, the route TEMPLATE (``/api/v1/meals/{meal_id}``,
  never the real path with ids), the request id, exception TYPES, stack frames (file, line,
  function) and counts. Exception messages are left out because they can hold user input or SQL
  parameters; the full details stay in the server logs (by request id or time).
* Throttled in memory (the API runs without Redis): the same alert is emailed at most once per
  repeat window (15 minutes for crashes, 30 minutes for named alerts unless the caller says
  otherwise), and at most ``HOURLY_CAP`` emails per process per hour. The next email for that
  alert says how many repeats were skipped.
* Sending runs in a background task, so a slow mail server never delays a response, and a failed
  send is logged (type only) and never raises.
"""

from __future__ import annotations

import asyncio
import time
import traceback
from collections.abc import Callable, Mapping
from datetime import UTC, datetime

import structlog

from app.integrations.email import PlainEmailSender

log = structlog.get_logger(__name__)

REPEAT_WINDOW_S = 15 * 60
ALERT_REPEAT_S = 30 * 60
HOURLY_CAP = 30
HOUR_S = 3600
MAX_FRAMES = 25

Fact = str | int | float


def _frames(exc: BaseException) -> list[str]:
    """``file:line in function`` for each frame, innermost last; no source text, no locals."""
    summary = traceback.extract_tb(exc.__traceback__)[-MAX_FRAMES:]
    return [f"  {frame.filename}:{frame.lineno} in {frame.name}" for frame in summary]


def _ascii(text: str) -> str:
    return "".join(ch if " " <= ch <= "~" else "?" for ch in text)[:120]


class ErrorAlerts:
    def __init__(
        self,
        *,
        sender: PlainEmailSender,
        to: str | None,
        environment: str,
        app_version: str,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._sender = sender
        self._to = to
        self._env = environment
        self._version = app_version
        self._clock = clock
        self._last_sent: dict[tuple[str, str], float] = {}
        self._skipped: dict[tuple[str, str], int] = {}
        self._hour_start = clock()
        self._hour_count = 0
        self._tasks: set[asyncio.Task[None]] = set()

    @property
    def enabled(self) -> bool:
        return bool(self._to)

    def _allow(self, key: tuple[str, str], repeat_s: float) -> bool:
        now = self._clock()
        if now - self._hour_start >= HOUR_S:
            self._hour_start, self._hour_count = now, 0
        last = self._last_sent.get(key)
        if (last is not None and now - last < repeat_s) or self._hour_count >= HOURLY_CAP:
            self._skipped[key] = self._skipped.get(key, 0) + 1
            return False
        self._last_sent[key] = now
        self._hour_count += 1
        return True

    def _header(self) -> list[str]:
        return [
            f"Environment : {self._env}",
            f"Version     : {self._version}",
            f"Time (UTC)  : {datetime.now(UTC).strftime('%Y-%m-%d %H:%M:%S')}",
        ]

    # ------------------------------------------------------------------ crashes
    def build(
        self, *, where: str, exc: BaseException, request_id: str | None, skipped: int
    ) -> tuple[str, str]:
        """(subject, body) of a crash email. Public for tests."""
        exc_type = type(exc).__name__
        subject = _ascii(f"[NaraaCare {self._env}] {exc_type} in {where}")
        lines = [
            "An error happened while running NaraaCare.",
            "",
            *self._header(),
            f"Where       : {_ascii(where)}",
            f"Error type  : {exc_type}",
            f"Request id  : {_ascii(request_id or '-')}",
        ]
        if skipped:
            lines.append(f"Repeats     : {skipped} more of this error were not emailed")
        lines += [
            "",
            "Stack (innermost last):",
            *_frames(exc),
            "",
            "The error message is left out on purpose (it can contain user data).",
            "Search the server logs for the request id or the time above for full details.",
        ]
        return subject, "\n".join(lines)

    def report(self, *, where: str, exc: BaseException, request_id: str | None = None) -> None:
        """Queue a crash email. Never raises; does nothing when ERROR_ALERT_EMAIL is unset."""
        if not self._to:
            return
        key = (_ascii(where), type(exc).__name__)
        if not self._allow(key, REPEAT_WINDOW_S):
            return
        skipped = self._skipped.pop(key, 0)
        self._queue(
            lambda: self.build(where=where, exc=exc, request_id=request_id, skipped=skipped)
        )

    # ------------------------------------------------------------------ named alerts
    def build_alert(
        self,
        *,
        section: str,
        title: str,
        trigger: str,
        facts: Mapping[str, Fact],
        action: str,
        exc: BaseException | None,
        skipped: int,
    ) -> tuple[str, str]:
        """(subject, body) of a named alert. Public for tests."""
        subject = _ascii(f"[NaraaCare {self._env}] ALERT: {title}")
        lines = [
            f"Alert       : {_ascii(title)}",
            f"Doc section : {_ascii(section)}",
            f"Trigger     : {_ascii(trigger)}",
            "",
            *self._header(),
        ]
        lines += [f"{_ascii(name):<12}: {_ascii(str(value))}" for name, value in facts.items()]
        if skipped:
            lines.append(f"Repeats     : {skipped} more of this alert were not emailed")
        lines += ["", f"What to do  : {_ascii(action)}"]
        if exc is not None:
            lines += ["", f"Error type  : {type(exc).__name__}", "Stack (innermost last):"]
            lines += _frames(exc)
        lines += [
            "",
            "No user data is included. Search the server logs around the time above for details.",
        ]
        return subject, "\n".join(lines)

    def alert(
        self,
        *,
        code: str,
        section: str,
        title: str,
        trigger: str,
        facts: Mapping[str, Fact],
        action: str,
        key: str = "",
        repeat_s: float = ALERT_REPEAT_S,
        exc: BaseException | None = None,
    ) -> None:
        """Queue a named alert email (throttled per code + key). Never raises."""
        if not self._to:
            return
        throttle = (f"alert:{code}", _ascii(key))
        if not self._allow(throttle, repeat_s):
            return
        skipped = self._skipped.pop(throttle, 0)
        self._queue(
            lambda: self.build_alert(
                section=section,
                title=title,
                trigger=trigger,
                facts=facts,
                action=action,
                exc=exc,
                skipped=skipped,
            )
        )
        log.warning("owner_alert", code=code)

    # ------------------------------------------------------------------ sending
    def _queue(self, build: Callable[[], tuple[str, str]]) -> None:
        to = self._to
        if not to:
            return
        try:
            subject, body = build()
            task = asyncio.get_running_loop().create_task(self._send(to, subject, body))
        except Exception as build_exc:  # an alert must never turn into a second error
            log.warning("error_alert_failed", exc_type=type(build_exc).__name__)
            return
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def _send(self, to: str, subject: str, body: str) -> None:
        try:
            await self._sender.send_plain(to, subject, body)
            log.info("error_alert_sent")
        except Exception as exc:
            log.warning("error_alert_failed", exc_type=type(exc).__name__)

    async def drain(self) -> None:
        """Wait for queued alerts (shutdown, worker jobs and tests)."""
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
