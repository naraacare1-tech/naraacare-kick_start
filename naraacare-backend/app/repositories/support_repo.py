"""Help & Support (doc 04 section 2.13) and sync (section 2.14). Stored routine calls only; the
daily limits, ownership and the plain-text rule are enforced in the database. The ``ops``
functions are granted to the worker role alone."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

CREATE_TICKET = db_call(
    "CALL support.pr_create_ticket(:user_id, :category, :description, :screenshot_key, NULL, NULL)"
)
CREATE_FEATURE_REQUEST = db_call(
    "CALL support.pr_create_feature_request(:user_id, :title, :benefit, NULL)"
)
UNFORWARDED = db_call("SELECT * FROM ops.fn_support_unforwarded(:limit)")
MARK_FORWARDED = db_call("CALL ops.pr_mark_support_forwarded(:kind, :item_id, :ok)")
CHANGES = db_call("SELECT * FROM app.fn_changes_since(:user_id, :after_at, :after_id, :limit)")


async def create_ticket(
    session: DbSession,
    user_id: UUID,
    *,
    category: str,
    description: str,
    screenshot_key: str | None,
) -> Mapping[str, Any]:
    return (
        await session.fetch_one(
            CREATE_TICKET,
            user_id=user_id,
            category=category,
            description=description,
            screenshot_key=screenshot_key,
        )
        or {}
    )


async def create_feature_request(
    session: DbSession, user_id: UUID, *, title: str, benefit: str
) -> UUID:
    row = await session.fetch_one(
        CREATE_FEATURE_REQUEST, user_id=user_id, title=title, benefit=benefit
    )
    request_id: UUID = (row or {})["o_request_id"]
    return request_id


async def unforwarded(session: DbSession, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(UNFORWARDED, limit=limit)


async def mark_forwarded(session: DbSession, kind: str, item_id: UUID, *, ok: bool) -> None:
    await session.execute(MARK_FORWARDED, kind=kind, item_id=item_id, ok=ok)


async def changes(
    session: DbSession,
    user_id: UUID,
    *,
    after_at: datetime | None,
    after_id: UUID | None,
    limit: int,
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(
        CHANGES, user_id=user_id, after_at=after_at, after_id=after_id, limit=limit
    )
