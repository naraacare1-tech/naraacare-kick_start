"""Firebase Cloud Messaging, HTTP v1 API (doc 03, Session 09).

Called directly over HTTPS with the shared HTTP client instead of firebase-admin: the same OAuth 2.0
service-account flow (an RS256-signed assertion exchanged for a one-hour access token), without the
gRPC/Google Cloud dependency tree (smaller install and audit surface, doc 07).

* Push texts are fixed templates per reminder type, never health values (OQ-41: lock screens are
  public). ``data`` carries only a type code and a fixed deep link.
* The access token comes from ``GoogleTokenSource`` (cached until 5 minutes before expiry).
* An ``UNREGISTERED`` answer reports the token as dead, so the worker wipes it.
* Tokens, keys and responses are never logged; failures log the status code only.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from http import HTTPStatus
from typing import Any

import httpx2
import structlog

from app.integrations.google_oauth import GoogleTokenSource, ServiceAccount

log = structlog.get_logger(__name__)

SCOPE = "https://www.googleapis.com/auth/firebase.messaging"


class PushResult(StrEnum):
    SENT = "sent"
    DEAD_TOKEN = "dead_token"  # noqa: S105  # nosec B105 - a result code, not a secret
    FAILED = "failed"


@dataclass(frozen=True, slots=True)
class PushMessage:
    title: str
    body: str
    kind: str
    deep_link: str


# Generic texts only (OQ-41). Localisation of push texts arrives with the notification centre (S14).
TEMPLATES: dict[str, PushMessage] = {
    "hydration": PushMessage(
        "Time for some water",
        "A few sips keep your avatar happy.",
        "hydration",
        "naraacare://home/hydration",
    ),
    "nutrition": PushMessage(
        "Log your meal",
        "Add what you ate to keep your day on track.",
        "nutrition",
        "naraacare://home/nutrition",
    ),
    "sleep": PushMessage(
        "Wind down",
        "Getting ready for bed? Log your sleep in the morning.",
        "sleep",
        "naraacare://home",
    ),
    "daily_checkin": PushMessage(
        "Daily check-in",
        "Take a moment to check in with your avatars.",
        "daily_checkin",
        "naraacare://home",
    ),
    "health_profile": PushMessage(
        "Keep your profile current",
        "Review your health profile for accurate goals.",
        "health_profile",
        "naraacare://settings",
    ),
    "day_ending_soon": PushMessage(
        "Your day is ending soon",
        "There is still time to reach today's water goal.",
        "day_ending_soon",
        "naraacare://home/hydration",
    ),
}

# Social pushes (S12): the notification row's deep link replaces the default one. Never the message
# text, a name or a health value (OQ-41); the app shows the details after it opens.
SOCIAL_TEMPLATES: dict[str, PushMessage] = {
    "connection_request": PushMessage(
        "New connection request",
        "Someone wants to connect with you on NaraaCare.",
        "connection_request",
        "naraacare://connections",
    ),
    "connection_accepted": PushMessage(
        "Request accepted",
        "You have a new connection.",
        "connection_accepted",
        "naraacare://connections",
    ),
    "circle_invite": PushMessage(
        "Care Circle invite",
        "You have been invited to a Care Circle.",
        "circle_invite",
        "naraacare://circles",
    ),
    "circle_message": PushMessage(
        "New message",
        "There is a new message in your Care Circle.",
        "circle_message",
        "naraacare://circles",
    ),
    "circle_mention": PushMessage(
        "You were mentioned",
        "Someone mentioned you in your Care Circle.",
        "circle_mention",
        "naraacare://circles",
    ),
    "circle_goal_completed": PushMessage(
        "Goal reached",
        "A member of your Care Circle reached a goal today.",
        "circle_goal_completed",
        "naraacare://circles",
    ),
    "circle_member_joined": PushMessage(
        "New member",
        "Someone joined your Care Circle.",
        "circle_member_joined",
        "naraacare://circles",
    ),
    "circle_member_left": PushMessage(
        "Circle update",
        "A member left your Care Circle.",
        "circle_member_left",
        "naraacare://circles",
    ),
    "circle_admin_granted": PushMessage(
        "You are an admin",
        "You can now manage your Care Circle.",
        "circle_admin_granted",
        "naraacare://circles",
    ),
    "circle_removed": PushMessage(
        "Circle update",
        "You are no longer a member of a Care Circle.",
        "circle_removed",
        "naraacare://circles",
    ),
    "circle_deleted": PushMessage(
        "Circle update",
        "A Care Circle you were in was deleted.",
        "circle_deleted",
        "naraacare://circles",
    ),
    # Session 14: personal progress and reports (same fan-out, own preference switches).
    "streak_milestone": PushMessage(
        "Streak milestone",
        "You reached a new streak milestone. Keep it going!",
        "streak_milestone",
        "naraacare://profile/streak",
    ),
    "report_ready": PushMessage(
        "Your report is ready",
        "Your NaraaCare report is ready to download.",
        "report_ready",
        "naraacare://profile/reports",
    ),
    "report_failed": PushMessage(
        "Report not created",
        "We could not create your report. Please try again.",
        "report_failed",
        "naraacare://profile/reports",
    ),
}


class FcmClient:
    def __init__(
        self,
        http: httpx2.AsyncClient,
        account: ServiceAccount,
        *,
        api_base_url: str,
        token_url: str,
        timeout_s: float = 5.0,
    ) -> None:
        self.http = http
        self.account = account
        self.send_url = f"{api_base_url.rstrip('/')}/v1/projects/{account.project_id}/messages:send"
        self.timeout_s = timeout_s
        self.tokens = GoogleTokenSource(
            http, account, scope=SCOPE, token_url=token_url, timeout_s=timeout_s
        )

    @staticmethod
    def payload(token: str, message: PushMessage) -> dict[str, Any]:
        return {
            "message": {
                "token": token,
                "notification": {"title": message.title, "body": message.body},
                "data": {"type": message.kind, "deep_link": message.deep_link},
                "android": {"priority": "normal"},
                "apns": {"headers": {"apns-priority": "5"}},
            }
        }

    async def send(self, token: str, message: PushMessage) -> PushResult:
        try:
            access = await self.tokens.token()
            if access is None:
                return PushResult.FAILED
            response = await self.http.post(
                self.send_url,
                json=self.payload(token, message),
                headers={"Authorization": f"Bearer {access}"},
                timeout=self.timeout_s,
            )
        except httpx2.HTTPError as exc:
            log.warning("fcm_send_error", error=type(exc).__name__)
            return PushResult.FAILED
        if response.status_code == HTTPStatus.OK:
            return PushResult.SENT
        if response.status_code in {
            HTTPStatus.BAD_REQUEST,
            HTTPStatus.NOT_FOUND,
        } and _is_dead_token(response):
            return PushResult.DEAD_TOKEN
        if response.status_code == HTTPStatus.UNAUTHORIZED:
            self.tokens.invalidate()  # expired early: fetch a new one next time
        log.warning("fcm_send_failed", status=response.status_code)
        return PushResult.FAILED


def _is_dead_token(response: httpx2.Response) -> bool:
    try:
        details = response.json()["error"].get("details", [])
    except (ValueError, KeyError, TypeError, AttributeError):
        return False
    codes = {d.get("errorCode") for d in details if isinstance(d, dict)}
    # Only UNREGISTERED is certain: INVALID_ARGUMENT can also mean a bad message, and wiping a
    # working token on our own mistake would silently stop that user's reminders.
    return "UNREGISTERED" in codes
