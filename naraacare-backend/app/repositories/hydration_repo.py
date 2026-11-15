"""Hydration and workouts (doc 04 section 2.5). Stored routine calls only; the status maths is the
pure engine in ``app.domain.hydration.status``."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

DAY_INPUTS = db_call("SELECT hydration.fn_day_inputs(:user_id, :on_date) AS inputs")
INTAKES = db_call("SELECT * FROM hydration.fn_intakes(:user_id, :on_date, :intake_id)")
DRINKS = db_call("SELECT * FROM hydration.fn_drinks_for_user(:user_id)")
LOG_INTAKE = db_call(
    "CALL hydration.pr_log_intake(:user_id, :intake_id, :logged_at, :drink_code, "
    ":custom_drink_id, :volume_ml, :source, NULL, NULL)"
)
UPDATE_INTAKE = db_call(
    "CALL hydration.pr_update_intake(:user_id, :intake_id, :version, :volume_ml, :drink_code, "
    ":custom_drink_id, NULL)"
)
DELETE_INTAKE = db_call("CALL hydration.pr_delete_intake(:user_id, :intake_id, :version)")
SET_TEMPERATURE = db_call("CALL hydration.pr_set_temperature(:user_id, :temperature_c, NULL)")
SAVE_CUSTOM_DRINK = db_call(
    "CALL hydration.pr_save_custom_drink(:user_id, :name, :factor, :estimated_by, NULL)"
)
UPSERT_SUMMARY = db_call(
    "CALL hydration.pr_upsert_daily_summary(:user_id, :on_date, :need_ml, :food_water_ml, "
    ":goal_completed, :calc_version, NULL)"
)
WORKOUTS = db_call("SELECT * FROM activity.fn_workouts(:user_id, :on_date, :workout_id)")
LOG_WORKOUT = db_call(
    "CALL activity.pr_log_workout(:user_id, :workout_id, :performed_at, :workout_type, "
    ":duration_min, NULL, NULL)"
)
DELETE_WORKOUT = db_call("CALL activity.pr_delete_workout(:user_id, :workout_id, :version)")


async def day_inputs(session: DbSession, user_id: UUID, on_date: date | None) -> Mapping[str, Any]:
    raw = await session.fetch_value(DAY_INPUTS, user_id=user_id, on_date=on_date)
    data: Mapping[str, Any] = json.loads(raw) if isinstance(raw, str | bytes) else raw
    return data


async def intakes(
    session: DbSession, user_id: UUID, on_date: date | None, intake_id: UUID | None = None
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(INTAKES, user_id=user_id, on_date=on_date, intake_id=intake_id)


async def drinks(session: DbSession, user_id: UUID) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(DRINKS, user_id=user_id)


async def log_intake(
    session: DbSession,
    user_id: UUID,
    *,
    intake_id: UUID,
    logged_at: datetime,
    drink_code: str | None,
    custom_drink_id: UUID | None,
    volume_ml: int,
    source: str,
) -> tuple[str, date]:
    row = await session.fetch_one(
        LOG_INTAKE,
        user_id=user_id,
        intake_id=intake_id,
        logged_at=logged_at,
        drink_code=drink_code,
        custom_drink_id=custom_drink_id,
        volume_ml=volume_ml,
        source=source,
    )
    row = row or {}
    return str(row["o_status"]), row["o_local_date"]


async def update_intake(
    session: DbSession,
    user_id: UUID,
    intake_id: UUID,
    *,
    version: int,
    volume_ml: int | None,
    drink_code: str | None,
    custom_drink_id: UUID | None,
) -> None:
    await session.fetch_one(
        UPDATE_INTAKE,
        user_id=user_id,
        intake_id=intake_id,
        version=version,
        volume_ml=volume_ml,
        drink_code=drink_code,
        custom_drink_id=custom_drink_id,
    )


async def delete_intake(session: DbSession, user_id: UUID, intake_id: UUID, version: int) -> None:
    await session.execute(DELETE_INTAKE, user_id=user_id, intake_id=intake_id, version=version)


async def set_temperature(session: DbSession, user_id: UUID, temperature_c: Decimal) -> date:
    row = await session.fetch_one(SET_TEMPERATURE, user_id=user_id, temperature_c=temperature_c)
    local_date: date = (row or {})["o_local_date"]
    return local_date


async def save_custom_drink(
    session: DbSession, user_id: UUID, *, name: str, factor: Decimal, estimated_by: str
) -> UUID:
    row = await session.fetch_one(
        SAVE_CUSTOM_DRINK, user_id=user_id, name=name, factor=factor, estimated_by=estimated_by
    )
    custom_drink_id: UUID = (row or {})["o_custom_drink_id"]
    return custom_drink_id


async def upsert_summary(
    session: DbSession,
    user_id: UUID,
    *,
    on_date: date,
    need_ml: int,
    food_water_ml: Decimal,
    goal_completed: bool,
    calc_version: str,
) -> bool:
    row = await session.fetch_one(
        UPSERT_SUMMARY,
        user_id=user_id,
        on_date=on_date,
        need_ml=need_ml,
        food_water_ml=food_water_ml,
        goal_completed=goal_completed,
        calc_version=calc_version,
    )
    return bool((row or {}).get("o_first_completion"))


async def workouts(
    session: DbSession, user_id: UUID, on_date: date | None, workout_id: UUID | None = None
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(
        WORKOUTS, user_id=user_id, on_date=on_date, workout_id=workout_id
    )


async def log_workout(
    session: DbSession,
    user_id: UUID,
    *,
    workout_id: UUID,
    performed_at: datetime,
    workout_type: str,
    duration_min: int,
) -> tuple[str, date]:
    row = await session.fetch_one(
        LOG_WORKOUT,
        user_id=user_id,
        workout_id=workout_id,
        performed_at=performed_at,
        workout_type=workout_type,
        duration_min=duration_min,
    )
    row = row or {}
    return str(row["o_status"]), row["o_local_date"]


async def delete_workout(session: DbSession, user_id: UUID, workout_id: UUID, version: int) -> None:
    await session.execute(DELETE_WORKOUT, user_id=user_id, workout_id=workout_id, version=version)
