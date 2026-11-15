"""Reports (doc 04 section 2.11) and the streak (section 2.7). Stored routine calls only; tier
rules, the daily limit, idempotency and ownership are enforced in the database. The ``ops``
functions are granted to the worker role alone."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

STREAK = db_call("SELECT * FROM app.fn_streak(:user_id, :month)")
CREATE_JOB = db_call(
    "CALL report.pr_create_report_job(:user_id, :idempotency_key, :kind, :period_from, :period_to, "
    "CAST(:sections AS text[]), NULL, NULL, NULL)"
)
JOBS = db_call("SELECT * FROM report.fn_report_jobs(:user_id, :report_id, :before, :limit)")
CLAIM_JOBS = db_call("SELECT * FROM ops.fn_claim_report_jobs(:limit)")
REPORT_DAYS = db_call("SELECT * FROM ops.fn_report_days(:report_id)")
REPORT_EXTRAS = db_call("SELECT ops.fn_report_extras(:report_id) AS extras")
RECORD_INSIGHT_USAGE = db_call(
    "CALL ops.pr_record_insight_usage(:report_id, :model, :input_tokens, :output_tokens, "
    ":cache_write_tokens, :cache_read_tokens, :cost_micro_inr)"
)
FINISH_JOB = db_call(
    "CALL ops.pr_finish_report_job(:report_id, :ok, :storage_key, :size_bytes, :error_code)"
)
EXPIRE_REPORTS = db_call("SELECT * FROM ops.fn_expire_reports(:limit)")


async def streak(session: DbSession, user_id: UUID, month: date | None) -> Mapping[str, Any]:
    return await session.fetch_one(STREAK, user_id=user_id, month=month) or {}


async def create_job(
    session: DbSession,
    user_id: UUID,
    *,
    idempotency_key: UUID,
    kind: str,
    period_from: date | None,
    period_to: date | None,
    sections: Sequence[str],
) -> Mapping[str, Any]:
    return (
        await session.fetch_one(
            CREATE_JOB,
            user_id=user_id,
            idempotency_key=idempotency_key,
            kind=kind,
            period_from=period_from,
            period_to=period_to,
            sections=list(sections),
        )
        or {}
    )


async def jobs(
    session: DbSession,
    user_id: UUID,
    *,
    report_id: UUID | None = None,
    before: datetime | None = None,
    limit: int = 20,
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(
        JOBS, user_id=user_id, report_id=report_id, before=before, limit=limit
    )


async def claim_jobs(session: DbSession, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(CLAIM_JOBS, limit=limit)


async def report_days(session: DbSession, report_id: UUID) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(REPORT_DAYS, report_id=report_id)


async def report_extras(session: DbSession, report_id: UUID) -> dict[str, Any]:
    """Numbers for the report pages (previous-period averages, meal shares, counts, targets)."""
    value = await session.fetch_value(REPORT_EXTRAS, report_id=report_id)
    if isinstance(value, str):
        value = json.loads(value)
    return dict(value) if isinstance(value, dict) else {}


async def record_insight_usage(
    session: DbSession,
    report_id: UUID,
    *,
    model: str,
    input_tokens: int,
    output_tokens: int,
    cache_write_tokens: int,
    cache_read_tokens: int,
    cost_micro_inr: int,
) -> None:
    await session.execute(
        RECORD_INSIGHT_USAGE,
        report_id=report_id,
        model=model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_write_tokens=cache_write_tokens,
        cache_read_tokens=cache_read_tokens,
        cost_micro_inr=cost_micro_inr,
    )


async def finish_job(
    session: DbSession,
    report_id: UUID,
    *,
    ok: bool,
    storage_key: str | None = None,
    size_bytes: int | None = None,
    error_code: str | None = None,
) -> None:
    await session.execute(
        FINISH_JOB,
        report_id=report_id,
        ok=ok,
        storage_key=storage_key,
        size_bytes=size_bytes,
        error_code=error_code,
    )


async def expire_reports(session: DbSession, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(EXPIRE_REPORTS, limit=limit)
