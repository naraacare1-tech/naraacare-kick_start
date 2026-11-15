"""Store billing (doc 04 section 2.12, doc 06 section 9, doc 07 SEC-6.1-6.3, Session 11).

Rules:
* The app's own purchase state is never trusted: a purchase counts only after the store confirms it
  (Play Developer API for Android, Apple's signed JWS for iOS). The app finishes the purchase only
  after this API answers 200.
* A purchase token / original transaction id belongs to one account; reuse on another account is
  refused (409 PURCHASE_TOKEN_IN_USE) and logged as a security event by the database.
* Webhooks (Play RTDN through Pub/Sub, App Store Server Notifications v2) are authenticated (OIDC /
  Apple certificate chain), processed once per notification id, and always re-read the authoritative
  state from the verified data or the store API, never from the unauthenticated envelope alone.
* The entitlement is read from the database on every request (no cache), so features unlock or
  lock at once.
* Purchase tokens are stored in plain text (uniqueness, reconcile; owner decision, 2026-11-03); they
  are never logged.
"""

from __future__ import annotations

import base64
import binascii
import hashlib
import json
from collections.abc import Mapping
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Literal
from uuid import UUID

import structlog

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain.entitlements.service import Entitlement, EntitlementService
from app.integrations.app_store import AppleJwsVerifier, AppleVerificationError, renewal_auto_renew
from app.integrations.google_play import GooglePlayClient, PlayError, PlaySubscription
from app.integrations.pubsub_auth import PubSubAuthError, PubSubVerifier
from app.repositories import billing_repo
from app.repositories.base import Database

log = structlog.get_logger(__name__)

PLATFORM = {"android": "google_play", "ios": "app_store"}


def entitlement_out(e: Entitlement) -> dict[str, Any]:
    return {
        "tier": e.tier,
        "source": e.source,
        "expires_at": e.expires_at,
        "features": e.features,
        "limits": e.limits,
    }


def encode_cursor(at: datetime) -> str:
    return base64.urlsafe_b64encode(at.isoformat().encode()).decode().rstrip("=")


def decode_cursor(cursor: str | None) -> datetime | None:
    if not cursor:
        return None
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)).decode()
        at = datetime.fromisoformat(raw)
    except (ValueError, binascii.Error, UnicodeDecodeError):
        raise AppError(ErrorCode.VALIDATION_FAILED, fields=["cursor"]) from None
    if at.tzinfo is None:
        raise AppError(ErrorCode.VALIDATION_FAILED, fields=["cursor"])
    return at


class BillingService:
    def __init__(
        self,
        *,
        db: Database,
        entitlements: EntitlementService,
        play: GooglePlayClient | None,
        apple: AppleJwsVerifier | None,
        pubsub: PubSubVerifier | None,
        package_name: str,
        manage_urls: Mapping[str, str],
    ) -> None:
        self.db = db
        self.entitlements = entitlements
        self.play = play
        self.apple = apple
        self.pubsub = pubsub
        self.package_name = package_name
        self.manage_urls = manage_urls

    # ------------------------------------------------------------------ reads
    async def plans(self) -> dict[str, Any]:
        rows = await self.db.run(billing_repo.plans, readonly=True)
        reverse = {v: k for k, v in PLATFORM.items()}
        return {
            "plans": [
                {
                    "platform": reverse[r["platform"]],
                    "product_id": r["product_id"],
                    "tier": r["tier_code"],
                    "period": "monthly" if r["period"] == "p1m" else "yearly",
                    "display_price_inr": float(r["display_price_inr"]),
                }
                for r in rows
            ]
        }

    async def subscription(self, principal: Principal) -> dict[str, Any]:
        entitlement = await self.entitlements.get(principal.user_id)
        row = await self.db.run(
            lambda s: billing_repo.subscription(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        if row is None:
            return {"tier": entitlement.tier, "source": entitlement.source, "status": None}
        platform = "android" if row["platform"] == "google_play" else "ios"
        return {
            "tier": entitlement.tier,
            "source": entitlement.source,
            "status": row["status"],
            "platform": platform,
            "product_id": row["product_id"],
            "period": "monthly" if row["period"] == "p1m" else "yearly",
            "period_end": row["current_period_end"].isoformat(),
            "auto_renew": bool(row["auto_renew"]),
            "manage_url": self.manage_urls[platform],
        }

    async def history(self, principal: Principal, cursor: str | None, limit: int) -> dict[str, Any]:
        before = decode_cursor(cursor)
        rows = await self.db.run(
            lambda s: billing_repo.history(s, principal.user_id, before, limit),
            user_id=principal.user_id,
            readonly=True,
        )
        items = [
            {
                "date": r["occurred_at"].isoformat(),
                "product_id": r["product_id"],
                "platform": "android" if r["platform"] == "google_play" else "ios",
                "type": r["type"],
                "amount": float(Decimal(r["amount_micros"]) / 1_000_000),
                "currency": r["currency"],
            }
            for r in rows
        ]
        next_cursor = encode_cursor(rows[-1]["occurred_at"]) if len(rows) == limit else None
        return {"items": items, "next_cursor": next_cursor}

    # ------------------------------------------------------------------ verify
    async def verify(
        self, principal: Principal, body: Mapping[str, Any], idempotency_key: UUID
    ) -> dict[str, Any]:
        # A retried request (same Idempotency-Key) is safe: the database upserts by purchase token.
        if body["platform"] == "android":
            await self._verify_play(principal, body)
        else:
            await self._verify_apple(principal, body)

        return entitlement_out(await self.entitlements.get(principal.user_id))

    async def _bind(self, principal: Principal, state: dict[str, Any]) -> None:
        _, status = await self.db.run(
            lambda s: billing_repo.upsert_subscription(s, principal.user_id, **state),
            user_id=principal.user_id,
        )
        if status == "token_in_use":
            raise AppError(ErrorCode.PURCHASE_TOKEN_IN_USE)

    async def _verify_play(self, principal: Principal, body: Mapping[str, Any]) -> None:
        token = body.get("purchase_token")
        if self.play is None or not token:
            raise AppError(ErrorCode.PURCHASE_INVALID)
        try:
            sub = await self.play.subscription(token)
        except PlayError:
            raise AppError(ErrorCode.PURCHASE_INVALID) from None
        if sub.product_id != body["product_id"]:
            raise AppError(ErrorCode.PURCHASE_INVALID)
        await self._bind(
            principal,
            {
                "platform": "google_play",
                "product_id": sub.product_id,
                "token": token,
                "original_transaction_id": None,
                "status": sub.status,
                "auto_renew": sub.auto_renew,
                "period_start": sub.period_start,
                "period_end": sub.period_end,
                "environment": sub.environment,
            },
        )
        if not sub.acknowledged and not await self.play.acknowledge(sub.product_id, token):
            # Not fatal: the reconcile job retries; Play only refunds after 3 days.
            log.warning("play_acknowledge_pending")
        await self._record_play_order(sub, token)

    async def _record_play_order(self, sub: PlaySubscription, token: str) -> None:
        if not sub.order_id:
            return
        plans = await self.db.run(billing_repo.plans, readonly=True)
        price = next(
            (
                p["display_price_inr"]
                for p in plans
                if p["platform"] == "google_play" and p["product_id"] == sub.product_id
            ),
            Decimal(0),
        )
        # subscriptionsv2 carries no price: history shows the list price; receipts come from Play.
        await self.db.run(
            lambda s: billing_repo.record_transaction(
                s,
                platform="google_play",
                token=token,
                original_transaction_id=None,
                store_transaction_id=_safe_ref(sub.order_id or ""),
                type="purchase" if ".." not in (sub.order_id or "") else "renewal",
                amount_micros=int(Decimal(price) * 1_000_000),
                currency="INR",
                occurred_at=sub.period_start,
            )
        )

    async def _verify_apple(self, principal: Principal, body: Mapping[str, Any]) -> None:
        jws = body.get("signed_transaction")
        if self.apple is None or not jws:
            raise AppError(ErrorCode.PURCHASE_INVALID)
        try:
            txn = self.apple.transaction(jws)
        except AppleVerificationError:
            raise AppError(ErrorCode.PURCHASE_INVALID) from None
        if txn.product_id != body["product_id"]:
            raise AppError(ErrorCode.PURCHASE_INVALID)
        now = datetime.now(UTC)
        status = "revoked" if txn.revoked else ("active" if txn.expires_date > now else "expired")
        await self._bind(
            principal,
            {
                "platform": "app_store",
                "product_id": txn.product_id,
                "token": None,  # nosec B105 - App Store purchases have no token
                "original_transaction_id": txn.original_transaction_id,
                "status": status,
                "auto_renew": True,
                "period_start": min(txn.purchase_date, txn.expires_date),
                "period_end": txn.expires_date,
                "environment": txn.environment,
            },
        )
        await self.db.run(
            lambda s: billing_repo.record_transaction(
                s,
                platform="app_store",
                token=None,
                original_transaction_id=txn.original_transaction_id,
                store_transaction_id=txn.transaction_id,
                type="purchase" if txn.transaction_id == txn.original_transaction_id else "renewal",
                amount_micros=max(txn.price_micros, 0),
                currency=txn.currency,
                occurred_at=txn.purchase_date,
            )
        )

    # ------------------------------------------------------------------ webhooks
    async def _once(
        self,
        platform: str,
        uid: str,
        type_: str,
        raw: bytes,
        handler: Any,
    ) -> None:
        sha = hashlib.sha256(raw).hexdigest()
        status = await self.db.run(
            lambda s: billing_repo.record_notification(
                s, platform=platform, uid=_safe_ref(uid), type_=_safe_code(type_), sha256=sha
            )
        )
        if status == "duplicate":
            return
        try:
            outcome: Literal["processed", "ignored"] = await handler()
        except Exception:
            await self.db.run(
                lambda s: billing_repo.finish_notification(
                    s, platform=platform, uid=_safe_ref(uid), status="failed"
                )
            )
            raise
        await self.db.run(
            lambda s: billing_repo.finish_notification(
                s, platform=platform, uid=_safe_ref(uid), status=outcome
            )
        )

    async def _apply(self, **state: Any) -> None:
        await self.db.run(lambda s: billing_repo.apply_state(s, **state))

    async def webhook_google(self, authorization: str | None, raw: bytes) -> None:
        if self.pubsub is None or self.play is None:
            raise AppError(ErrorCode.UNAUTHENTICATED)
        try:
            await self.pubsub.verify(authorization)
        except PubSubAuthError:
            raise AppError(ErrorCode.UNAUTHENTICATED) from None
        try:
            envelope = json.loads(raw)
            message = envelope["message"]
            data = json.loads(base64.b64decode(message["data"]))
            message_id = str(message["messageId"])
        except (ValueError, KeyError, TypeError, binascii.Error):
            raise AppError(ErrorCode.BAD_REQUEST) from None
        if not isinstance(data, dict) or data.get("packageName") != self.package_name:
            raise AppError(ErrorCode.BAD_REQUEST)
        play = self.play

        async def handle() -> Literal["processed", "ignored"]:
            sub_note = data.get("subscriptionNotification")
            voided = data.get("voidedPurchaseNotification")
            if isinstance(sub_note, dict) and isinstance(sub_note.get("purchaseToken"), str):
                token = sub_note["purchaseToken"]
                try:
                    sub = await play.subscription(token)
                except PlayError:
                    return "ignored"
                await self._apply(
                    platform="google_play",
                    token=token,
                    original_transaction_id=None,
                    product_id=sub.product_id,
                    status=sub.status,
                    auto_renew=sub.auto_renew,
                    period_start=sub.period_start,
                    period_end=sub.period_end,
                    environment=sub.environment,
                )
                return "processed"
            if isinstance(voided, dict) and isinstance(voided.get("purchaseToken"), str):
                await self._apply(
                    platform="google_play",
                    token=voided["purchaseToken"],
                    original_transaction_id=None,
                    product_id=None,
                    status="refunded",
                    auto_renew=False,
                    period_start=None,
                    period_end=None,
                    environment=None,
                )
                return "processed"
            return "ignored"  # testNotification, one-time products

        kind = next(
            (k for k in ("subscriptionNotification", "voidedPurchaseNotification") if k in data),
            "other",
        )
        await self._once("google_play", message_id, _snake(kind), raw, handle)

    async def webhook_apple(self, signed_payload: str) -> None:
        if self.apple is None:
            raise AppError(ErrorCode.UNAUTHENTICATED)
        apple = self.apple
        try:
            note = apple.verify(signed_payload)
        except AppleVerificationError:
            raise AppError(ErrorCode.UNAUTHENTICATED) from None
        data = note.get("data") or {}
        if data.get("bundleId") != apple.bundle_id:
            raise AppError(ErrorCode.BAD_REQUEST)
        uid = str(note.get("notificationUUID") or "")
        type_ = str(note.get("notificationType") or "unknown")
        subtype = str(note.get("subtype") or "")

        async def handle() -> Literal["processed", "ignored"]:
            signed_txn = data.get("signedTransactionInfo")
            if not isinstance(signed_txn, str):
                return "ignored"
            try:
                txn = apple.transaction(signed_txn)
            except AppleVerificationError:
                return "ignored"
            auto_renew = renewal_auto_renew(apple, data.get("signedRenewalInfo"))
            status = _apple_status(type_, subtype, txn.expires_date)
            if status is None:
                return "ignored"
            await self._apply(
                platform="app_store",
                token=None,
                original_transaction_id=txn.original_transaction_id,
                product_id=txn.product_id,
                status=status,
                auto_renew=auto_renew,
                period_start=min(txn.purchase_date, txn.expires_date),
                period_end=txn.expires_date,
                environment=txn.environment,
            )
            if type_ in {"DID_RENEW", "SUBSCRIBED", "REFUND"}:
                await self.db.run(
                    lambda s: billing_repo.record_transaction(
                        s,
                        platform="app_store",
                        token=None,
                        original_transaction_id=txn.original_transaction_id,
                        store_transaction_id=_safe_ref(
                            txn.transaction_id + (":refund" if type_ == "REFUND" else "")
                        ),
                        type={"REFUND": "refund", "SUBSCRIBED": "purchase"}.get(type_, "renewal"),
                        amount_micros=max(txn.price_micros, 0),
                        currency=txn.currency,
                        occurred_at=txn.purchase_date,
                    )
                )
            return "processed"

        await self._once("app_store", uid, type_.lower(), signed_payload.encode(), handle)


APPLE_FIXED_STATUS = {
    "SUBSCRIBED": "active",
    "DID_RENEW": "active",
    "OFFER_REDEEMED": "active",
    "EXPIRED": "expired",
    "GRACE_PERIOD_EXPIRED": "expired",
    "REFUND": "refunded",
    "REVOKE": "revoked",
}


def _apple_status(type_: str, subtype: str, expires: datetime) -> str | None:
    """billing.subscription.status for an App Store notification (None = nothing to change)."""
    if type_ == "DID_CHANGE_RENEWAL_STATUS":
        if expires <= datetime.now(UTC):
            return "expired"
        # Cancel = auto-renew off: STAR stays until the period end (doc 06 section 9).
        return "canceled" if subtype == "AUTO_RENEW_DISABLED" else "active"
    if type_ == "DID_FAIL_TO_RENEW":
        return "in_grace" if subtype == "GRACE_PERIOD" else "on_hold"
    return APPLE_FIXED_STATUS.get(type_)


def _snake(name: str) -> str:
    out = "".join("_" + c.lower() if c.isupper() else c for c in name)
    return out.strip("_")


def _safe_code(value: str) -> str:
    """Notification types become common.code values (lower case, [a-z0-9_.])."""
    cleaned = "".join(c for c in value.lower() if c.isalnum() or c in "_.")[:63]
    return cleaned if cleaned and cleaned[0].isalpha() else "unknown"


def _safe_ref(value: str) -> str:
    """Store ids become common.opaque_ref values ([A-Za-z0-9._:-], max 200)."""
    cleaned = "".join(c for c in value if c.isalnum() or c in "._:-")[:200]
    return cleaned if cleaned and cleaned[0].isalnum() else "x" + cleaned[:199]
