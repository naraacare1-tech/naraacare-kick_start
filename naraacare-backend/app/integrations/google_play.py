"""Google Play Developer API (Session 11, doc 07 SEC-6.1): the authoritative state of a
subscription purchase token, and acknowledgement (Play refunds purchases that are not acknowledged
within 3 days).

Called over HTTPS with the shared HTTP client and a service-account token (``GoogleTokenSource``)
instead of google-api-python-client (smaller install and audit surface). The package name is fixed
by configuration, so a token from another app is refused by Google itself. Tokens are never logged.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from http import HTTPStatus
from typing import Any
from urllib.parse import quote

import httpx2
import structlog

from app.integrations.google_oauth import GoogleTokenSource, ServiceAccount

log = structlog.get_logger(__name__)

SCOPE = "https://www.googleapis.com/auth/androidpublisher"

# subscriptionsv2 state -> billing.subscription.status
STATES = {
    "SUBSCRIPTION_STATE_ACTIVE": "active",
    "SUBSCRIPTION_STATE_IN_GRACE_PERIOD": "in_grace",
    "SUBSCRIPTION_STATE_ON_HOLD": "on_hold",
    "SUBSCRIPTION_STATE_PAUSED": "paused",
    "SUBSCRIPTION_STATE_CANCELED": "canceled",
    "SUBSCRIPTION_STATE_EXPIRED": "expired",
    "SUBSCRIPTION_STATE_PENDING_PURCHASE_CANCELED": "expired",
}


class PlayError(Exception):
    """The purchase could not be verified (unknown token, wrong app, Google unavailable)."""


@dataclass(frozen=True, slots=True)
class PlaySubscription:
    product_id: str
    status: str
    auto_renew: bool
    period_start: datetime
    period_end: datetime
    environment: str
    acknowledged: bool
    order_id: str | None


def _ts(value: object) -> datetime:
    return datetime.fromisoformat(str(value).replace("Z", "+00:00")).astimezone(UTC)


def parse_subscription(body: dict[str, Any]) -> PlaySubscription:
    state = str(body.get("subscriptionState", ""))
    if state not in STATES or not body.get("lineItems"):
        raise PlayError("pending or unknown purchase state")
    item = body["lineItems"][0]
    start = _ts(body["startTime"])
    end = _ts(item["expiryTime"])
    return PlaySubscription(
        product_id=str(item["productId"]),
        status=STATES[state],
        auto_renew=bool((item.get("autoRenewingPlan") or {}).get("autoRenewEnabled", False)),
        period_start=min(start, end),
        period_end=end,
        environment="sandbox" if "testPurchase" in body else "production",
        acknowledged=body.get("acknowledgementState") == "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
        order_id=str(body["latestOrderId"]) if body.get("latestOrderId") else None,
    )


class GooglePlayClient:
    def __init__(
        self,
        http: httpx2.AsyncClient,
        account: ServiceAccount,
        *,
        package_name: str,
        api_base_url: str,
        token_url: str,
        timeout_s: float = 8.0,
    ) -> None:
        self.http = http
        package = quote(package_name, safe="")
        self.base = f"{api_base_url.rstrip('/')}/androidpublisher/v3/applications/{package}"
        self.timeout_s = timeout_s
        self.tokens = GoogleTokenSource(
            http, account, scope=SCOPE, token_url=token_url, timeout_s=timeout_s
        )

    async def _headers(self) -> dict[str, str]:
        access = await self.tokens.token()
        if access is None:
            raise PlayError("no access token")
        return {"Authorization": f"Bearer {access}"}

    async def subscription(self, purchase_token: str) -> PlaySubscription:
        url = f"{self.base}/purchases/subscriptionsv2/tokens/{quote(purchase_token, safe='')}"
        try:
            response = await self.http.get(
                url, headers=await self._headers(), timeout=self.timeout_s
            )
        except httpx2.HTTPError as exc:
            raise PlayError(type(exc).__name__) from None
        if response.status_code != HTTPStatus.OK:
            if response.status_code == HTTPStatus.UNAUTHORIZED:
                self.tokens.invalidate()
            log.warning("play_verify_failed", status=response.status_code)
            raise PlayError(f"status {response.status_code}")
        return parse_subscription(response.json())

    async def acknowledge(self, product_id: str, purchase_token: str) -> bool:
        url = (
            f"{self.base}/purchases/subscriptions/{quote(product_id, safe='')}"
            f"/tokens/{quote(purchase_token, safe='')}:acknowledge"
        )
        try:
            response = await self.http.post(
                url, headers=await self._headers(), json={}, timeout=self.timeout_s
            )
        except (httpx2.HTTPError, PlayError):
            return False
        if response.status_code not in {HTTPStatus.OK, HTTPStatus.NO_CONTENT}:
            log.warning("play_acknowledge_failed", status=response.status_code)
            return False
        return True
