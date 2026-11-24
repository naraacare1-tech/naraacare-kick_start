"""Profile, onboarding, settings, targets (doc 04 section 2.2, doc 06).

* Name and medical conditions are encrypted with the column as associated data; only the owner's
  requests decrypt them.
* Every write that changes a calculation input recomputes TODAY's targets only (doc 06 section 1).
* BMI guardrails: a blocked goal is refused (422 GOAL_NOT_ALLOWED) when it is saved, not just when
  targets are computed, so the profile never holds a combination the rules forbid.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import date, datetime
from decimal import Decimal
from typing import Any
from zoneinfo import ZoneInfo

import structlog

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain import targets as targets_domain
from app.domain.common.calc_context import CalcContext
from app.domain.common.rounding import half_up
from app.domain.entitlements import service as entitlements
from app.domain.nutrition import calculator as nutrition
from app.domain.reference import ReferenceCache
from app.repositories import privacy_repo, profile_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)

# API field -> profile column / procedure parameter
COLUMN = {
    "biological_sex": "biological_sex",
    "avatar_code": "avatar_code",
    "age_years": "age_years",
    "height_cm": "height_cm",
    "weight_kg": "weight_kg",
    "target_weight_kg": "target_weight_kg",
    "weight_goal": "weight_goal_code",
    "activity_level": "activity_level_code",
    "body_type": "body_type_code",
}
STEP_FIELDS: dict[int, tuple[frozenset[str], frozenset[str]]] = {
    # step: (required fields, optional fields)
    1: (frozenset({"biological_sex", "avatar_code", "full_name"}), frozenset()),
    2: (frozenset({"height_cm"}), frozenset()),
    3: (frozenset({"weight_kg", "weight_goal"}), frozenset()),
    4: (frozenset({"target_weight_kg"}), frozenset({"medical_condition_codes"})),
    5: (frozenset({"age_years", "activity_level"}), frozenset()),
    6: (frozenset({"body_type"}), frozenset()),
}
GOAL_STEP = 3  # height is known from step 2, so the BMI guardrails apply when the goal is saved
LAST_STEP = 6
CALC_FIELDS = frozenset(
    {
        "biological_sex",
        "age_years",
        "height_cm",
        "weight_kg",
        "weight_goal",
        "activity_level",
        "body_type",
    }
)


def local_today(timezone: str) -> date:
    return datetime.now(ZoneInfo(timezone)).date()


@dataclass(frozen=True, slots=True)
class ProfileRow:
    row: Mapping[str, Any]
    email: str
    full_name: str | None
    condition_codes: list[str]


class ProfileService:
    def __init__(self, *, db: Database, reference: ReferenceCache) -> None:
        self.db = db
        self.reference = reference

    # ------------------------------------------------------------------ reading
    @staticmethod
    def unpack(row: Mapping[str, Any]) -> ProfileRow:
        """Email, name and condition codes are stored in plain text (owner decision, 2026-11-03)."""
        name = row.get("full_name")
        return ProfileRow(
            row=row,
            email=str(row["email"]),
            full_name=str(name) if name else None,
            condition_codes=list(row.get("medical_conditions") or []),
        )

    async def load(self, principal: Principal) -> tuple[ProfileRow, entitlements.Entitlement]:
        async def work(s: DbSession) -> tuple[Mapping[str, Any] | None, entitlements.Entitlement]:
            return await profile_repo.get_profile(s, principal.user_id), await entitlements.load(
                s, principal.user_id
            )

        row, entitlement = await self.db.run(work, user_id=principal.user_id, readonly=True)
        if row is None:
            raise AppError(ErrorCode.NOT_FOUND)
        return self.unpack(row), entitlement

    async def refresh_outdated_targets(self, principal: Principal, d: ProfileRow) -> bool:
        """Recompute TODAY's targets once when they come from an older calculation version.

        Owner 2026-11-24 moved to the 2026-11 MVP formulas (calc_version 2026.2). Without this, an
        existing user would keep the old targets until they edited their profile. Called on
        GET /me (every app start), so each user moves over on their next visit; past days keep their
        snapshots. A profile whose goal is no longer allowed keeps its targets (the next edit
        resolves it). Never raises: GET /me must not fail because of it. True when it recomputed.
        """
        if d.row["onboarding_completed_at"] is None:
            return False
        ctx = await self.reference.calc_context()

        async def work(s: DbSession) -> bool:
            latest = await profile_repo.latest_targets(s, principal.user_id)
            if latest is None or latest["calc_version"] == ctx.calc_version:
                return False
            row = await profile_repo.get_profile(s, principal.user_id)
            if row is None:
                return False
            today = local_today(row["timezone"])
            try:
                inputs, t = self._compute(ctx, row, today)
            except AppError:
                return False
            # No profile field changes; the snapshot replaces today's targets and refreshes today's
            # nutrition summary (app.pr_update_profile).
            await profile_repo.update_profile(
                s, principal.user_id, {}, targets_domain.snapshot(inputs, t, ctx)
            )
            return True

        try:
            refreshed = await self.db.run(work, user_id=principal.user_id)
        except Exception as exc:  # GET /me must still answer
            log.warning("targets_refresh_failed", error=type(exc).__name__)
            return False
        if refreshed:
            log.info("targets_refreshed", calc_version=ctx.calc_version)
        return refreshed

    @staticmethod
    def profile_out(d: ProfileRow, today: date | None = None) -> dict[str, Any]:
        row = d.row
        age = row["age_years"]
        if age is not None and today is not None:
            age = targets_domain.current_age(age, row["age_recorded_on"], today)
        return {
            "biological_sex": row["biological_sex"],
            "avatar_code": row["avatar_code"],
            "full_name": d.full_name,
            "age_years": age,
            "height_cm": row["height_cm"],
            "weight_kg": row["weight_kg"],
            "target_weight_kg": row["target_weight_kg"],
            "weight_goal": row["weight_goal_code"],
            "activity_level": row["activity_level_code"],
            "body_type": row["body_type_code"],
            "medical_condition_codes": d.condition_codes,
        }

    def me(self, d: ProfileRow, entitlement: entitlements.Entitlement) -> dict[str, Any]:
        row = d.row
        return {
            "user_id": row["user_id"],
            "email": d.email,
            "role": row["role"],
            "tier": entitlement.tier,
            "username": row["username"],
            # Local sign-up date: the monthly report picker starts at this month (V028).
            "member_since": row.get("member_since"),
            "onboarding": {
                "current_step": row["onboarding_step"],
                "completed": row["onboarding_completed_at"] is not None,
            },
            "profile": self.profile_out(d, local_today(row["timezone"])),
            "settings": {
                "height_unit": row["height_unit"],
                "weight_unit": row["weight_unit"],
                "temperature_unit": row["temperature_unit"],
                "timezone": row["timezone"],
                "locale": row["locale"],
                "sleep_start_local": row["sleep_start_local"],
                "wake_local": row["wake_local"],
                "sleep_goal_min": row["sleep_goal_min"],
                "biometric_lock": row["biometric_lock"],
            },
            # Profile header counts (S14): accepted connections and active circles.
            "counts": {
                "connections": row.get("connections_count") or 0,
                "circles": row.get("circles_count") or 0,
                "current_streak": row["current_streak"],
                "longest_streak": row["longest_streak"],
            },
        }

    # ------------------------------------------------------------------ validation helpers
    def _to_params(self, ctx: CalcContext, fields: Mapping[str, Any]) -> dict[str, Any]:
        """API fields -> procedure parameters (condition codes checked)."""
        params: dict[str, Any] = {COLUMN[k]: v for k, v in fields.items() if k in COLUMN}
        if fields.get("full_name") is not None:
            params["full_name"] = fields["full_name"]
        codes = fields.get("medical_condition_codes")
        if codes is not None:
            unknown = [c for c in codes if c not in ctx.medical_condition_codes]
            if unknown or len(set(codes)) != len(codes):
                raise AppError(ErrorCode.VALIDATION_FAILED, fields=["medical_condition_codes"])
            params["medical_conditions"] = sorted(codes)
        return params

    @staticmethod
    def _check_goal(
        ctx: CalcContext, weight: Any, height: Any, goal: Any, *, new_choice: bool = True
    ) -> None:
        # Retired goals (owner 2026-11-07: five on offer) are kept for profiles that have one, but
        # cannot be chosen again.
        retired = goal in ctx.weight_goals and not ctx.weight_goals[goal].offered
        if new_choice and retired:
            raise AppError(ErrorCode.GOAL_NOT_ALLOWED, fields=["weight_goal"])
        if weight is None or height is None or goal is None:
            return
        bmi_value = nutrition.bmi_exact(Decimal(weight), Decimal(height))
        if goal in nutrition.bmi_category(ctx, bmi_value).blocked_goal_codes:
            raise AppError(ErrorCode.GOAL_NOT_ALLOWED, fields=["weight_goal"])

    @staticmethod
    def _inputs(values: Mapping[str, Any], today: date) -> targets_domain.ProfileInputs:
        required = (
            "biological_sex",
            "age_years",
            "height_cm",
            "weight_kg",
            "activity_level_code",
            "weight_goal_code",
            "body_type_code",
        )
        if any(values.get(k) is None for k in required):
            raise AppError(ErrorCode.ONBOARDING_INCOMPLETE)
        return targets_domain.ProfileInputs(
            sex=values["biological_sex"],
            age_years=targets_domain.current_age(
                int(values["age_years"]), values.get("age_recorded_on"), today
            ),
            height_cm=Decimal(values["height_cm"]),
            weight_kg=Decimal(values["weight_kg"]),
            activity_level=values["activity_level_code"],
            weight_goal=values["weight_goal_code"],
            body_type=values["body_type_code"],
        )

    def _compute(
        self, ctx: CalcContext, values: Mapping[str, Any], today: date
    ) -> tuple[targets_domain.ProfileInputs, targets_domain.Targets]:
        inputs = self._inputs(values, today)
        try:
            return inputs, targets_domain.calculate(ctx, inputs)
        except nutrition.GoalNotAllowedError:
            raise AppError(ErrorCode.GOAL_NOT_ALLOWED, fields=["weight_goal"]) from None

    # ------------------------------------------------------------------ onboarding
    async def onboarding(self, principal: Principal) -> dict[str, Any]:
        d, _ = await self.load(principal)
        return {
            "current_step": d.row["onboarding_step"],
            "completed": d.row["onboarding_completed_at"] is not None,
            "data_so_far": self.profile_out(d),
        }

    async def save_step(self, principal: Principal, step: int, fields: Mapping[str, Any]) -> int:
        required, optional = STEP_FIELDS[step]
        sent = {k for k, v in fields.items() if v is not None}
        missing = sorted(required - sent)
        extra = sorted(sent - required - optional)
        if missing or extra:
            raise AppError(ErrorCode.VALIDATION_FAILED, fields=missing + extra)
        ctx = await self.reference.calc_context()
        if step == 1 and not str(fields["avatar_code"]).startswith(f"{fields['biological_sex']}_"):
            raise AppError(ErrorCode.VALIDATION_FAILED, fields=["avatar_code"])
        params = self._to_params(ctx, fields)

        async def work(s: DbSession) -> int:
            if step == GOAL_STEP:
                row = await profile_repo.get_profile(s, principal.user_id)
                self._check_goal(
                    ctx, fields["weight_kg"], (row or {}).get("height_cm"), fields["weight_goal"]
                )
            return await profile_repo.save_onboarding_step(s, principal.user_id, step, params)

        return await self.db.run(work, user_id=principal.user_id)

    async def preview(self, principal: Principal) -> dict[str, Any]:
        d, _ = await self.load(principal)
        ctx = await self.reference.calc_context()
        _, t = self._compute(ctx, d.row, local_today(d.row["timezone"]))
        return self.preview_out(t)

    @staticmethod
    def preview_out(t: targets_domain.Targets) -> dict[str, Any]:
        n = t.nutrition
        return {
            "calc_version": t.calc_version,
            "bmi": n.bmi,
            "bmi_category": n.bmi_category,
            "healthy_weight_range_kg": t.healthy_weight_range_kg,
            "targets": {
                "kcal": n.base_target_kcal,
                "carbs_g": n.carbs_g,
                "fat_g": n.fat_g,
                "protein_g": n.protein_g,
                "safety_override": n.safety_override,
            },
            "water_need_ml": t.water_need_ml,
        }

    async def complete(
        self,
        principal: Principal,
        consents: list[dict[str, Any]],
        *,
        ip: str | None,
    ) -> dict[str, Any]:
        ctx = await self.reference.calc_context()

        async def work(s: DbSession) -> Mapping[str, Any] | None:
            row = await profile_repo.get_profile(s, principal.user_id)
            if row is None or row["onboarding_step"] < LAST_STEP:
                raise AppError(ErrorCode.ONBOARDING_INCOMPLETE)
            inputs, t = self._compute(ctx, row, local_today(row["timezone"]))
            await profile_repo.complete_onboarding(
                s,
                principal.user_id,
                snapshot=targets_domain.snapshot(inputs, t, ctx),
                consents=consents,
                app_version=None,
                ip=ip,
            )
            return await profile_repo.latest_targets(s, principal.user_id)

        snapshot = await self.db.run(work, user_id=principal.user_id)
        return self.targets_out(snapshot)

    # ------------------------------------------------------------------ profile and settings
    async def update_profile(
        self, principal: Principal, fields: Mapping[str, Any]
    ) -> dict[str, Any]:
        sent = {k: v for k, v in fields.items() if v is not None}
        if not sent:
            raise AppError(ErrorCode.VALIDATION_FAILED, fields=["body"])
        ctx = await self.reference.calc_context()
        params = self._to_params(ctx, sent)
        avatar = sent.get("avatar_code")

        async def work(s: DbSession) -> tuple[Mapping[str, Any] | None, entitlements.Entitlement]:
            row = await profile_repo.get_profile(s, principal.user_id)
            if row is None or row["onboarding_completed_at"] is None:
                raise AppError(ErrorCode.ONBOARDING_INCOMPLETE)
            merged = {**row, **params}
            if avatar is not None and not str(avatar).startswith(f"{merged['biological_sex']}_"):
                raise AppError(ErrorCode.VALIDATION_FAILED, fields=["avatar_code"])
            snapshot = None
            if CALC_FIELDS & sent.keys():
                today = local_today(row["timezone"])
                if "age_years" in sent:
                    merged["age_recorded_on"] = today
                self._check_goal(
                    ctx,
                    merged["weight_kg"],
                    merged["height_cm"],
                    merged["weight_goal_code"],
                    new_choice=merged["weight_goal_code"] != row.get("weight_goal_code"),
                )
                inputs, t = self._compute(ctx, merged, today)
                snapshot = targets_domain.snapshot(inputs, t, ctx)
            await profile_repo.update_profile(s, principal.user_id, params, snapshot)
            return await profile_repo.get_profile(s, principal.user_id), await entitlements.load(
                s, principal.user_id
            )

        row, entitlement = await self.db.run(work, user_id=principal.user_id)
        if row is None:
            raise AppError(ErrorCode.NOT_FOUND)
        targets = await self.targets_today(principal) if CALC_FIELDS & sent.keys() else None
        return {"me": self.me(self.unpack(row), entitlement), "targets_today": targets}

    async def update_settings(self, principal: Principal, settings: Mapping[str, Any]) -> None:
        await self.db.run(
            lambda s: profile_repo.update_settings(s, principal.user_id, settings),
            user_id=principal.user_id,
        )

    async def goal_options(
        self, principal: Principal, weight_kg: Decimal | None, height_cm: Decimal | None
    ) -> dict[str, Any]:
        ctx = await self.reference.calc_context()
        if weight_kg is None or height_cm is None:
            d, _ = await self.load(principal)
            weight_kg = weight_kg if weight_kg is not None else d.row["weight_kg"]
            height_cm = height_cm if height_cm is not None else d.row["height_cm"]
        if weight_kg is None or height_cm is None:
            raise AppError(ErrorCode.ONBOARDING_INCOMPLETE)
        weight, height = Decimal(weight_kg), Decimal(height_cm)
        bmi_value = nutrition.bmi_exact(weight, height)
        category = nutrition.bmi_category(ctx, bmi_value)
        return {
            "bmi": half_up(bmi_value, 1),
            "category": category.code,
            "allowed_goals": nutrition.allowed_goals(ctx, category),
            "healthy_weight_range_kg": nutrition.healthy_weight_range(ctx, height),
        }

    @staticmethod
    def targets_out(row: Mapping[str, Any] | None) -> dict[str, Any]:
        if row is None:
            raise AppError(ErrorCode.ONBOARDING_INCOMPLETE)
        return {
            "effective_date": row["effective_date"],
            "calc_version": row["calc_version"],
            "bmi": row["bmi"],
            "bmi_category": row["bmi_category"],
            "nutrition": {
                "kcal": row["base_target_kcal"],
                "carbs_g": row["carbs_g"],
                "fat_g": row["fat_g"],
                "protein_g": row["protein_g"],
                "safety_override": row["safety_override"],
            },
            "water_need_ml": row["base_water_need_ml"],
        }

    async def targets_today(self, principal: Principal) -> dict[str, Any]:
        row = await self.db.run(
            lambda s: profile_repo.latest_targets(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return self.targets_out(row)

    # ------------------------------------------------------------------ username
    async def username_available(self, principal: Principal, username: str) -> bool:
        """The caller's own current username counts as available (the function excludes it)."""
        return await self.db.run(
            lambda s: profile_repo.username_available(s, username),
            user_id=principal.user_id,
            readonly=True,
        )

    async def set_username(self, principal: Principal, username: str) -> None:
        await self.db.run(
            lambda s: profile_repo.set_username(s, principal.user_id, username),
            user_id=principal.user_id,
        )

    # ------------------------------------------------------------------ consents
    async def consents(self, principal: Principal) -> list[Mapping[str, Any]]:
        rows = await self.db.run(
            lambda s: privacy_repo.current_consents(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return list(rows)

    async def record_consent(
        self, principal: Principal, consent: Mapping[str, Any], *, ip: str | None
    ) -> None:
        await self.db.run(
            lambda s: privacy_repo.record_consent(
                s,
                user_id=principal.user_id,
                purpose=consent["purpose"],
                policy_version=consent["policy_version"],
                granted=consent["granted"],
                app_version=None,
                ip=ip,
            ),
            user_id=principal.user_id,
        )
