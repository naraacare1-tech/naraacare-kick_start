"""Consents, privacy status, exports and deletion (doc 07 SEC-7, Session 15). Stored routine calls
only; limits, ownership and the 30-day grace are enforced in the database. The ``ops`` functions are
granted to the worker role alone. Consent records are append-only; the newest decision is in
force."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

RECORD_CONSENT = db_call(
    "CALL privacy.pr_record_consent("
    ":user_id, :purpose, :policy_version, :granted, :app_version, CAST(:ip AS inet), NULL)"
)
CURRENT_CONSENTS = db_call("SELECT * FROM privacy.fn_current_consents(:user_id)")
STATUS = db_call("SELECT privacy.fn_privacy_status(:user_id) AS status")
EXPORT = db_call("SELECT * FROM privacy.fn_exports(:user_id, :export_id)")
REQUEST_EXPORT = db_call(
    "CALL privacy.pr_request_export(:user_id, :idempotency_key, NULL, NULL, NULL)"
)
REQUEST_DELETION = db_call("CALL privacy.pr_request_deletion(:user_id, NULL, NULL)")
CANCEL_DELETION = db_call("CALL privacy.pr_cancel_deletion(:user_id, NULL)")
CLAIM_EXPORTS = db_call("SELECT * FROM ops.fn_claim_exports(:limit)")
EXPORT_USER = db_call("SELECT ops.fn_export_user(:user_id) AS data")
FINISH_EXPORT = db_call(
    "CALL ops.pr_finish_export(:export_id, :ok, :object_key, :size_bytes, :error_code)"
)
EXPIRE_EXPORTS = db_call("SELECT * FROM ops.fn_expire_exports(:limit)")
DUE_DELETIONS = db_call("SELECT * FROM ops.fn_due_deletions(:limit)")
USER_FILES = db_call("SELECT * FROM ops.fn_user_files(:user_id)")
MARK_RECEIPT = db_call("CALL ops.pr_mark_deletion_receipt(:user_id)")
DELETE_USER = db_call("CALL ops.pr_delete_user(:user_id, NULL)")
ROW_RETENTION = db_call("SELECT * FROM ops.fn_apply_row_retention()")
PARTITION_RETENTION = db_call("CALL ops.pr_apply_retention(NULL, NULL)")
EXPIRED_ATTACHMENTS = db_call("SELECT * FROM ops.fn_expired_attachments(:limit)")


def _json(value: Any) -> Any:
    return json.loads(value) if isinstance(value, str | bytes) else value


async def record_consent(
    session: DbSession,
    *,
    user_id: UUID,
    purpose: str,
    policy_version: str,
    granted: bool,
    app_version: str | None,
    ip: str | None,
) -> None:
    await session.fetch_one(
        RECORD_CONSENT,
        user_id=user_id,
        purpose=purpose,
        policy_version=policy_version,
        granted=granted,
        app_version=app_version,
        ip=ip,
    )


async def current_consents(session: DbSession, user_id: UUID) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(CURRENT_CONSENTS, user_id=user_id)


async def status(session: DbSession, user_id: UUID) -> dict[str, Any]:
    return dict(_json(await session.fetch_value(STATUS, user_id=user_id)) or {})


async def export(session: DbSession, user_id: UUID, export_id: UUID) -> Mapping[str, Any]:
    return await session.fetch_one(EXPORT, user_id=user_id, export_id=export_id) or {}


async def request_export(
    session: DbSession, user_id: UUID, idempotency_key: UUID
) -> Mapping[str, Any]:
    row = await session.fetch_one(REQUEST_EXPORT, user_id=user_id, idempotency_key=idempotency_key)
    return row or {}


async def request_deletion(session: DbSession, user_id: UUID) -> Mapping[str, Any]:
    return await session.fetch_one(REQUEST_DELETION, user_id=user_id) or {}


async def cancel_deletion(session: DbSession, user_id: UUID) -> bool:
    row = await session.fetch_one(CANCEL_DELETION, user_id=user_id)
    return bool((row or {}).get("o_cancelled"))


async def claim_exports(session: DbSession, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(CLAIM_EXPORTS, limit=limit)


async def export_user(session: DbSession, user_id: UUID) -> dict[str, Any]:
    return dict(_json(await session.fetch_value(EXPORT_USER, user_id=user_id)) or {})


async def finish_export(
    session: DbSession,
    export_id: UUID,
    *,
    ok: bool,
    object_key: str | None = None,
    size_bytes: int | None = None,
    error_code: str | None = None,
) -> None:
    await session.execute(
        FINISH_EXPORT,
        export_id=export_id,
        ok=ok,
        object_key=object_key,
        size_bytes=size_bytes,
        error_code=error_code,
    )


async def expire_exports(session: DbSession, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(EXPIRE_EXPORTS, limit=limit)


async def due_deletions(session: DbSession, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(DUE_DELETIONS, limit=limit)


async def user_files(session: DbSession, user_id: UUID) -> list[str]:
    return [str(r["object_key"]) for r in await session.fetch_all(USER_FILES, user_id=user_id)]


async def mark_receipt(session: DbSession, user_id: UUID) -> None:
    await session.execute(MARK_RECEIPT, user_id=user_id)


async def delete_user(session: DbSession, user_id: UUID) -> int:
    row = await session.fetch_one(DELETE_USER, user_id=user_id)
    return int((row or {}).get("o_archived") or 0)


async def apply_retention(session: DbSession) -> dict[str, int]:
    await session.fetch_one(PARTITION_RETENTION)
    return {str(r["item"]): int(r["purged"]) for r in await session.fetch_all(ROW_RETENTION)}


async def expired_attachments(session: DbSession, limit: int) -> list[str]:
    rows = await session.fetch_all(EXPIRED_ATTACHMENTS, limit=limit)
    return [str(r["object_key"]) for r in rows]
