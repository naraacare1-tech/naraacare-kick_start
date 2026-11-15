"""Rin AI (doc 04 section 2.10). Stored routine calls only; the STAR / consent gate, ownership and
the plain-text rule are enforced in the database (ai.fn_require_rin, RLS, common.safe_text)."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

CONTEXT = db_call("SELECT ai.fn_rin_context(:user_id) AS context")
LOOKUP = db_call("SELECT ai.fn_rin_lookup(:user_id, :kind, :day, :days) AS data")
USAGE_MONTH = db_call("SELECT * FROM ai.fn_usage_month(:user_id)")
CONVERSATIONS = db_call("SELECT * FROM ai.fn_conversations(:user_id, :query, :before, :limit)")
MESSAGES = db_call("SELECT * FROM ai.fn_messages(:user_id, :conversation_id, :before, :limit)")
HISTORY = db_call("SELECT * FROM ai.fn_history(:user_id, :conversation_id, :limit)")
PENDING_ACTION = db_call("SELECT * FROM ai.fn_pending_action(:user_id, :action_id)")
CREATE_CONVERSATION = db_call("CALL ai.pr_create_conversation(:user_id, :title, NULL)")
APPEND_MESSAGE = db_call(
    "CALL ai.pr_append_message(:user_id, :conversation_id, :role, :content, "
    ":client_message_id, :action_id, NULL, NULL)"
)
RECORD_USAGE = db_call(
    "CALL ai.pr_record_usage(:user_id, :feature, :model, :input_tokens, :output_tokens, "
    ":cache_write_tokens, :cache_read_tokens, :cost_micro_inr)"
)
CREATE_ACTION = db_call(
    "CALL ai.pr_create_pending_action(:user_id, :conversation_id, :kind, :payload, NULL, NULL)"
)
RESOLVE_ACTION = db_call(
    "CALL ai.pr_resolve_pending_action(:user_id, :action_id, :status, :result_id)"
)
DELETE_CONVERSATION = db_call("CALL ai.pr_delete_conversation(:user_id, :conversation_id)")
DELETE_MEMORY = db_call("CALL ai.pr_delete_memory(:user_id)")


def _json(value: Any) -> Any:
    return json.loads(value) if isinstance(value, str | bytes) else value


async def context(session: DbSession, user_id: UUID) -> dict[str, Any]:
    raw = await session.fetch_value(CONTEXT, user_id=user_id)
    return dict(_json(raw) or {})


async def lookup(
    session: DbSession, user_id: UUID, *, kind: str, day: date | None, days: int | None
) -> dict[str, Any]:
    """Rin's get_my_data tool: the user's own aggregates (ai.fn_rin_lookup)."""
    raw = await session.fetch_value(LOOKUP, user_id=user_id, kind=kind, day=day, days=days)
    return dict(_json(raw) or {})


async def usage_month(session: DbSession, user_id: UUID) -> tuple[int, datetime, datetime]:
    """(AI spend this local month in micro-rupees, when the cap resets, next local midnight)."""
    row = await session.fetch_one(USAGE_MONTH, user_id=user_id) or {}
    return int(row["used_micro_inr"]), row["resets_at"], row["next_local_midnight"]


async def conversations(
    session: DbSession, user_id: UUID, *, query: str | None, before: datetime | None, limit: int
) -> list[dict[str, Any]]:
    rows = await session.fetch_all(
        CONVERSATIONS, user_id=user_id, query=query, before=before, limit=limit
    )
    return [dict(r) for r in rows]


async def messages(
    session: DbSession,
    user_id: UUID,
    conversation_id: UUID,
    *,
    before: datetime | None,
    limit: int,
) -> list[dict[str, Any]]:
    rows = await session.fetch_all(
        MESSAGES, user_id=user_id, conversation_id=conversation_id, before=before, limit=limit
    )
    return [{**r, "action": _json(r["action"])} for r in rows]


async def history(
    session: DbSession, user_id: UUID, conversation_id: UUID, limit: int = 20
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(
        HISTORY, user_id=user_id, conversation_id=conversation_id, limit=limit
    )


async def pending_action(session: DbSession, user_id: UUID, action_id: UUID) -> dict[str, Any]:
    row = await session.fetch_one(PENDING_ACTION, user_id=user_id, action_id=action_id) or {}
    return {**row, "payload": _json(row.get("payload"))}


async def create_conversation(session: DbSession, user_id: UUID, title: str) -> UUID:
    row = await session.fetch_one(CREATE_CONVERSATION, user_id=user_id, title=title) or {}
    conversation_id: UUID = row["o_conversation_id"]
    return conversation_id


async def append_message(
    session: DbSession,
    user_id: UUID,
    conversation_id: UUID,
    *,
    role: str,
    content: str,
    client_message_id: UUID | None = None,
    action_id: UUID | None = None,
) -> tuple[UUID, str]:
    row = (
        await session.fetch_one(
            APPEND_MESSAGE,
            user_id=user_id,
            conversation_id=conversation_id,
            role=role,
            content=content,
            client_message_id=client_message_id,
            action_id=action_id,
        )
        or {}
    )
    return row["o_message_id"], str(row["o_status"])


async def record_usage(
    session: DbSession,
    user_id: UUID,
    *,
    feature: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
    cache_write_tokens: int = 0,
    cache_read_tokens: int = 0,
    cost_micro_inr: int = 0,
) -> None:
    await session.execute(
        RECORD_USAGE,
        user_id=user_id,
        feature=feature,
        model=model,
        input_tokens=input_tokens,
        output_tokens=output_tokens,
        cache_write_tokens=cache_write_tokens,
        cache_read_tokens=cache_read_tokens,
        cost_micro_inr=cost_micro_inr,
    )


async def create_action(
    session: DbSession,
    user_id: UUID,
    conversation_id: UUID | None,
    kind: str,
    payload: Mapping[str, Any],
) -> tuple[UUID, datetime]:
    row = (
        await session.fetch_one(
            CREATE_ACTION,
            user_id=user_id,
            conversation_id=conversation_id,
            kind=kind,
            payload=json.dumps(dict(payload), default=str),
        )
        or {}
    )
    return row["o_action_id"], row["o_expires_at"]


async def resolve_action(
    session: DbSession, user_id: UUID, action_id: UUID, status: str, result_id: UUID | None
) -> None:
    await session.execute(
        RESOLVE_ACTION, user_id=user_id, action_id=action_id, status=status, result_id=result_id
    )


async def delete_conversation(session: DbSession, user_id: UUID, conversation_id: UUID) -> None:
    await session.execute(DELETE_CONVERSATION, user_id=user_id, conversation_id=conversation_id)


async def delete_memory(session: DbSession, user_id: UUID) -> None:
    await session.execute(DELETE_MEMORY, user_id=user_id)
