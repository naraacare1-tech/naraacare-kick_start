"""Profile, onboarding, settings, username and targets (doc 04 section 2.2)."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

GET_PROFILE = db_call("SELECT * FROM app.fn_get_profile(:user_id)")
SAVE_ONBOARDING_STEP = db_call(
    "CALL app.pr_save_onboarding_step(:user_id, :step, :biological_sex, :avatar_code, "
    ":full_name, :height_cm, :weight_kg, :weight_goal_code, :target_weight_kg, "
    ":medical_conditions, :age_years, :activity_level_code, :body_type_code, NULL)"
)
COMPLETE_ONBOARDING = db_call(
    "CALL app.pr_complete_onboarding("
    ":user_id, :snapshot, :consents, :app_version, CAST(:ip AS inet), NULL)"
)
UPDATE_PROFILE = db_call(
    "CALL app.pr_update_profile(:user_id, :full_name, :biological_sex, :avatar_code, "
    ":age_years, :height_cm, :weight_kg, :target_weight_kg, :weight_goal_code, "
    ":activity_level_code, :body_type_code, :medical_conditions, :snapshot, NULL)"
)
UPDATE_SETTINGS = db_call(
    "CALL app.pr_update_settings(:user_id, :height_unit, :weight_unit, :temperature_unit, "
    ":timezone, :locale, :sleep_start_local, :wake_local, :biometric_lock)"
)
SET_USERNAME = db_call("CALL app.pr_set_username(:user_id, :username)")
USERNAME_AVAILABLE = db_call("SELECT app.fn_username_available(:username) AS available")
LATEST_TARGETS = db_call("SELECT * FROM app.fn_latest_target_snapshot(:user_id, :on_date)")

PROFILE_FIELDS = (
    "full_name",
    "biological_sex",
    "avatar_code",
    "age_years",
    "height_cm",
    "weight_kg",
    "target_weight_kg",
    "weight_goal_code",
    "activity_level_code",
    "body_type_code",
    "medical_conditions",
)


async def get_profile(session: DbSession, user_id: UUID) -> Mapping[str, Any] | None:
    return await session.fetch_one(GET_PROFILE, user_id=user_id)


async def save_onboarding_step(
    session: DbSession, user_id: UUID, step: int, fields: Mapping[str, object]
) -> int:
    params = {name: fields.get(name) for name in PROFILE_FIELDS if name != "age_years"}
    params["age_years"] = fields.get("age_years")
    row = await session.fetch_one(SAVE_ONBOARDING_STEP, user_id=user_id, step=step, **params)
    return int((row or {})["o_current_step"])


async def complete_onboarding(
    session: DbSession,
    user_id: UUID,
    *,
    snapshot: Mapping[str, Any],
    consents: list[dict[str, Any]],
    app_version: str | None,
    ip: str | None,
) -> Any:
    row = await session.fetch_one(
        COMPLETE_ONBOARDING,
        user_id=user_id,
        snapshot=json.dumps(snapshot),
        consents=json.dumps(consents),
        app_version=app_version,
        ip=ip,
    )
    return (row or {}).get("o_effective_date")


async def update_profile(
    session: DbSession,
    user_id: UUID,
    fields: Mapping[str, object],
    snapshot: Mapping[str, Any] | None,
) -> Any:
    params = {name: fields.get(name) for name in PROFILE_FIELDS}
    row = await session.fetch_one(
        UPDATE_PROFILE,
        user_id=user_id,
        snapshot=json.dumps(snapshot) if snapshot is not None else None,
        **params,
    )
    return (row or {}).get("o_effective_date")


async def update_settings(
    session: DbSession, user_id: UUID, settings: Mapping[str, object]
) -> None:
    await session.execute(UPDATE_SETTINGS, user_id=user_id, **settings)


async def set_username(session: DbSession, user_id: UUID, username: str) -> None:
    await session.execute(SET_USERNAME, user_id=user_id, username=username)


async def username_available(session: DbSession, username: str) -> bool:
    return bool(await session.fetch_value(USERNAME_AVAILABLE, username=username))


async def latest_targets(session: DbSession, user_id: UUID) -> Mapping[str, Any] | None:
    return await session.fetch_one(LATEST_TARGETS, user_id=user_id, on_date=None)
