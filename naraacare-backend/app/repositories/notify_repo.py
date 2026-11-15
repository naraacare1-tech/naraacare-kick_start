"""Devices, notification preferences and reminder schedules (doc 04 section 2.7), plus the
worker-only reminder fan-out (``ops`` functions granted to the worker role alone)."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

REGISTER_DEVICE = db_call(
    "CALL notify.pr_register_device(:user_id, :installation_id, :platform, :push_token, "
    ":app_version, NULL)"
)
REVOKE_DEVICE = db_call("CALL notify.pr_revoke_device(:user_id, :installation_id, NULL)")
PREFERENCES = db_call("SELECT notify.fn_notification_preferences(:user_id) AS preferences")
SET_PREFERENCES = db_call("CALL notify.pr_set_notification_preferences(:user_id, :preferences)")
REMINDERS = db_call("SELECT * FROM notify.fn_reminders(:user_id)")
SET_REMINDERS = db_call("CALL notify.pr_set_reminders(:user_id, :reminders)")
DUE_REMINDERS = db_call("SELECT * FROM ops.fn_due_reminders(:now)")
DAY_ENDING_SOON = db_call("SELECT * FROM ops.fn_day_ending_soon(:now, :hours, :window_min)")
REVOKE_PUSH_TOKEN = db_call("CALL ops.pr_revoke_push_token(:device_id)")
SOCIAL_PUSHES = db_call("SELECT * FROM ops.fn_social_pushes(:after, :until, :limit)")


async def register_device(
    session: DbSession,
    user_id: UUID,
    *,
    installation_id: UUID,
    platform: str,
    push_token: str | None,
    app_version: str,
) -> UUID:
    row = await session.fetch_one(
        REGISTER_DEVICE,
        user_id=user_id,
        installation_id=installation_id,
        platform=platform,
        push_token=push_token,
        app_version=app_version,
    )
    device_id: UUID = (row or {})["o_device_id"]
    return device_id


async def revoke_device(session: DbSession, user_id: UUID, installation_id: UUID) -> bool:
    row = await session.fetch_one(REVOKE_DEVICE, user_id=user_id, installation_id=installation_id)
    return bool((row or {}).get("o_revoked"))


async def preferences(session: DbSession, user_id: UUID) -> dict[str, bool]:
    raw = await session.fetch_value(PREFERENCES, user_id=user_id)
    data: dict[str, bool] = json.loads(raw) if isinstance(raw, str | bytes) else dict(raw)
    return data


async def set_preferences(session: DbSession, user_id: UUID, values: Mapping[str, bool]) -> None:
    await session.execute(SET_PREFERENCES, user_id=user_id, preferences=json.dumps(dict(values)))


async def reminders(session: DbSession, user_id: UUID) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(REMINDERS, user_id=user_id)


async def set_reminders(
    session: DbSession, user_id: UUID, items: Sequence[Mapping[str, Any]]
) -> None:
    await session.execute(SET_REMINDERS, user_id=user_id, reminders=json.dumps(list(items)))


async def due_reminders(session: DbSession, now: datetime) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(DUE_REMINDERS, now=now)


async def day_ending_soon(
    session: DbSession, now: datetime, hours: Decimal, window_min: int
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(DAY_ENDING_SOON, now=now, hours=hours, window_min=window_min)


async def revoke_push_token(session: DbSession, device_id: UUID) -> None:
    await session.execute(REVOKE_PUSH_TOKEN, device_id=device_id)


async def social_pushes(
    session: DbSession, after: datetime, until: datetime, limit: int
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(SOCIAL_PUSHES, after=after, until=until, limit=limit)
