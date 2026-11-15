"""Billing worker jobs (Session 11 steps 8-9). Scheduler only; the database routines they call are
granted to the worker role alone.

* ``tally_referrals`` (nightly): ``ops.pr_tally_referrals`` (active days, qualification, rewards).
* ``reconcile_subscriptions`` (every 6 h): re-reads subscriptions ending within 24 h or not verified
  for 6 h from the store (Play Developer API / App Store Server API) and applies the authoritative
  state, so a missed webhook cannot leave anyone with the wrong tier. Each subscription is handled
  on its own: one failure never stops the rest.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

import structlog

from app.integrations.app_store import (
    AppleJwsVerifier,
    AppleVerificationError,
    AppStoreApiClient,
    renewal_auto_renew,
)
from app.integrations.google_play import GooglePlayClient, PlayError
from app.repositories import billing_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)

# App Store "Get All Subscription Statuses" status -> billing.subscription.status
APPLE_STATUS = {1: "active", 2: "expired", 3: "on_hold", 4: "in_grace", 5: "revoked"}


@dataclass(slots=True)
class ReconcileStats:
    checked: int = 0
    updated: int = 0
    failed: int = 0


async def tally_referrals(db: Database) -> tuple[int, int]:
    qualified, rewarded = await db.run(billing_repo.tally)
    log.info("referral_tally", qualified=qualified, rewarded=rewarded)
    return qualified, rewarded


async def _apple_state(
    client: AppStoreApiClient, verifier: AppleJwsVerifier, original_id: str
) -> dict[str, Any] | None:
    body = await client.subscription_statuses(original_id)
    if not body:
        return None
    for group in body.get("data") or []:
        for item in group.get("lastTransactions") or []:
            if str(item.get("originalTransactionId")) != original_id:
                continue
            try:
                txn = verifier.transaction(str(item["signedTransactionInfo"]))
            except (AppleVerificationError, KeyError):
                return None
            status = APPLE_STATUS.get(int(item.get("status", 0)))
            if status is None:
                return None
            auto_renew = renewal_auto_renew(verifier, item.get("signedRenewalInfo"))
            if status == "active" and auto_renew is False:
                status = "canceled"  # auto-renew off: STAR until the period end
            return {
                "product_id": txn.product_id,
                "status": status,
                "auto_renew": auto_renew,
                "period_start": min(txn.purchase_date, txn.expires_date),
                "period_end": txn.expires_date,
                "environment": txn.environment,
            }
    return None


async def reconcile_subscriptions(
    *,
    db: Database,
    play: GooglePlayClient | None,
    app_store: AppStoreApiClient | None,
    apple: AppleJwsVerifier | None,
    limit: int = 200,
) -> ReconcileStats:
    stats = ReconcileStats()
    rows = await db.run(lambda s: billing_repo.to_reconcile(s, datetime.now(UTC), limit))
    for row in rows:
        stats.checked += 1
        try:
            if row["platform"] == "google_play" and play is not None and row["purchase_token"]:
                token = str(row["purchase_token"])
                sub = await play.subscription(token)
                state: dict[str, Any] | None = {
                    "product_id": sub.product_id,
                    "status": sub.status,
                    "auto_renew": sub.auto_renew,
                    "period_start": sub.period_start,
                    "period_end": sub.period_end,
                    "environment": sub.environment,
                }
                key = {"token": token, "original_transaction_id": None}
            elif row["platform"] == "app_store" and app_store is not None and apple is not None:
                state = await _apple_state(app_store, apple, str(row["original_transaction_id"]))
                key = {
                    "token": None,  # nosec B105 - App Store purchases have no token
                    "original_transaction_id": row["original_transaction_id"],
                }
            else:
                continue
        except PlayError as exc:
            stats.failed += 1
            log.warning("reconcile_failed", platform=row["platform"], error=type(exc).__name__)
            continue
        if state is None:
            stats.failed += 1
            continue
        platform = str(row["platform"])

        async def apply(
            session: DbSession,
            st: dict[str, Any] = state,
            k: dict[str, Any] = key,
            p: str = platform,
        ) -> UUID | None:
            return await billing_repo.apply_state(session, platform=p, **k, **st)

        await db.run(apply)
        stats.updated += 1
    log.info(
        "subscriptions_reconciled",
        checked=stats.checked,
        updated=stats.updated,
        failed=stats.failed,
    )
    return stats
