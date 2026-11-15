"""Billing and referral (doc 04 section 2.12). Stored routine calls only."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

PLANS = db_call("SELECT * FROM billing.fn_plans()")
SUBSCRIPTION = db_call("SELECT * FROM billing.fn_subscription(:user_id)")
HISTORY = db_call("SELECT * FROM billing.fn_billing_history(:user_id, :before, :limit)")
UPSERT_SUBSCRIPTION = db_call(
    "CALL billing.pr_upsert_subscription(:user_id, :platform, :product_id, :token, "
    ":original_transaction_id, :status, :auto_renew, :period_start, :period_end, :environment, "
    "NULL, NULL)"
)
APPLY_STATE = db_call(
    "CALL billing.pr_apply_store_state(:platform, :token, :original_transaction_id, "
    ":product_id, :status, :auto_renew, :period_start, :period_end, :environment, NULL)"
)
RECORD_TRANSACTION = db_call(
    "CALL billing.pr_record_transaction(:platform, :token, :original_transaction_id, "
    ":store_transaction_id, :type, :amount_micros, :currency, :occurred_at)"
)
RECORD_NOTIFICATION = db_call(
    "CALL billing.pr_record_store_notification(:platform, :uid, :type, :sha256, NULL)"
)
FINISH_NOTIFICATION = db_call("CALL billing.pr_finish_store_notification(:platform, :uid, :status)")
ENSURE_CODE = db_call("CALL billing.pr_ensure_referral_code(:user_id, NULL)")
ATTRIBUTE = db_call("CALL billing.pr_attribute_referral(:user_id, :code, :installation_id, NULL)")
PROGRESS = db_call("SELECT billing.fn_referral_progress(:user_id) AS progress")
TALLY = db_call("CALL ops.pr_tally_referrals(NULL, NULL, NULL)")
TO_RECONCILE = db_call("SELECT * FROM ops.fn_subscriptions_to_reconcile(:now, :limit)")


async def plans(session: DbSession) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(PLANS)


async def subscription(session: DbSession, user_id: UUID) -> Mapping[str, Any] | None:
    return await session.fetch_one(SUBSCRIPTION, user_id=user_id)


async def history(
    session: DbSession, user_id: UUID, before: datetime | None, limit: int
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(HISTORY, user_id=user_id, before=before, limit=limit)


async def upsert_subscription(
    session: DbSession, user_id: UUID, **state: Any
) -> tuple[UUID | None, str]:
    row = await session.fetch_one(UPSERT_SUBSCRIPTION, user_id=user_id, **state)
    row = row or {}
    return row.get("o_subscription_id"), str(row["o_status"])


async def apply_state(session: DbSession, **state: Any) -> UUID | None:
    row = await session.fetch_one(APPLY_STATE, **state)
    user_id: UUID | None = (row or {}).get("o_user_id")
    return user_id


async def record_transaction(session: DbSession, **txn: Any) -> None:
    await session.execute(RECORD_TRANSACTION, **txn)


async def record_notification(
    session: DbSession, *, platform: str, uid: str, type_: str, sha256: str
) -> str:
    row = await session.fetch_one(
        RECORD_NOTIFICATION, platform=platform, uid=uid, type=type_, sha256=sha256
    )
    return str((row or {})["o_status"])


async def finish_notification(session: DbSession, *, platform: str, uid: str, status: str) -> None:
    await session.execute(FINISH_NOTIFICATION, platform=platform, uid=uid, status=status)


async def ensure_code(session: DbSession, user_id: UUID) -> str:
    row = await session.fetch_one(ENSURE_CODE, user_id=user_id)
    return str((row or {})["o_code"])


async def attribute(session: DbSession, user_id: UUID, code: str, installation_id: UUID) -> str:
    row = await session.fetch_one(
        ATTRIBUTE, user_id=user_id, code=code, installation_id=installation_id
    )
    return str((row or {})["o_status"])


async def progress(session: DbSession, user_id: UUID) -> dict[str, Any]:
    raw = await session.fetch_value(PROGRESS, user_id=user_id)
    data: dict[str, Any] = json.loads(raw) if isinstance(raw, str | bytes) else dict(raw)
    return data


async def tally(session: DbSession) -> tuple[int, int]:
    row = await session.fetch_one(TALLY) or {}
    return int(row.get("o_qualified") or 0), int(row.get("o_rewarded") or 0)


async def to_reconcile(
    session: DbSession, now: datetime, limit: int
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(TO_RECONCILE, now=now, limit=limit)
