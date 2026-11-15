"""Sleep (doc 04 section 2.6). Stored routine calls only; counted minutes, the daily score and the
label are computed in the database from the calc constants (doc 06 section 4)."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

SUMMARY = db_call("SELECT sleep.fn_summary(:user_id, :on_date, :entry_id) AS summary")
LOG_ENTRY = db_call(
    "CALL sleep.pr_log_entry(:user_id, :entry_id, :sleep_start, :wake_time, :wakings, NULL, NULL)"
)
UPDATE_ENTRY = db_call(
    "CALL sleep.pr_update_entry(:user_id, :entry_id, :version, :sleep_start, :wake_time, "
    ":wakings, NULL)"
)
DELETE_ENTRY = db_call("CALL sleep.pr_delete_entry(:user_id, :entry_id, :version)")
SET_GOAL = db_call("CALL app.pr_set_sleep_goal(:user_id, :goal_min)")


def wakings_json(wakings: Sequence[Mapping[str, Any]]) -> str:
    return json.dumps(
        [
            {
                "woke_at": w["woke_at"].isoformat(),
                "back_asleep_at": w["back_asleep_at"].isoformat(),
            }
            for w in wakings
        ]
    )


async def summary(
    session: DbSession, user_id: UUID, on_date: date | None, entry_id: UUID | None = None
) -> dict[str, Any]:
    raw = await session.fetch_value(SUMMARY, user_id=user_id, on_date=on_date, entry_id=entry_id)
    data: dict[str, Any] = json.loads(raw) if isinstance(raw, str | bytes) else dict(raw)
    return data


async def log_entry(
    session: DbSession,
    user_id: UUID,
    *,
    entry_id: UUID,
    sleep_start: datetime,
    wake_time: datetime,
    wakings: Sequence[Mapping[str, Any]],
) -> tuple[str, date]:
    row = await session.fetch_one(
        LOG_ENTRY,
        user_id=user_id,
        entry_id=entry_id,
        sleep_start=sleep_start,
        wake_time=wake_time,
        wakings=wakings_json(wakings),
    )
    row = row or {}
    return str(row["o_status"]), row["o_local_date"]


async def update_entry(
    session: DbSession,
    user_id: UUID,
    entry_id: UUID,
    *,
    version: int,
    sleep_start: datetime,
    wake_time: datetime,
    wakings: Sequence[Mapping[str, Any]],
) -> None:
    await session.fetch_one(
        UPDATE_ENTRY,
        user_id=user_id,
        entry_id=entry_id,
        version=version,
        sleep_start=sleep_start,
        wake_time=wake_time,
        wakings=wakings_json(wakings),
    )


async def delete_entry(session: DbSession, user_id: UUID, entry_id: UUID, version: int) -> None:
    await session.execute(DELETE_ENTRY, user_id=user_id, entry_id=entry_id, version=version)


async def set_goal(session: DbSession, user_id: UUID, goal_min: int) -> None:
    await session.execute(SET_GOAL, user_id=user_id, goal_min=goal_min)
