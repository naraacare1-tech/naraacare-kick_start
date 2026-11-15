"""Daily targets for a profile: nutrition (doc 06 section 2) + base water need (section 3.4).

``build_snapshot`` produces the row ``app.pr_upsert_target_snapshot`` stores (keys = snapshot
columns) and the preview shown on the onboarding result page; both come from the same numbers, so
"preview equals completed snapshot" holds by construction.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from typing import Any

from app.domain.common.calc_context import CalcContext
from app.domain.common.rounding import half_up_float
from app.domain.hydration import calculator as hydration
from app.domain.nutrition import calculator as nutrition


@dataclass(frozen=True, slots=True)
class ProfileInputs:
    sex: str
    age_years: int
    height_cm: Decimal
    weight_kg: Decimal
    activity_level: str
    weight_goal: str
    body_type: str


@dataclass(frozen=True, slots=True)
class Targets:
    calc_version: str
    nutrition: nutrition.NutritionTargets
    hydration: hydration.HydrationBase
    healthy_weight_range_kg: tuple[int, int]

    @property
    def water_need_ml(self) -> int:
        return int(half_up_float(self.hydration.daily_need_ml))


def current_age(age_years: int, recorded_on: date | None, today: date) -> int:
    """Age = stated age + full years since it was stated (OQ-31: no date of birth is stored)."""
    if recorded_on is None:
        return age_years
    years = today.year - recorded_on.year
    if (today.month, today.day) < (recorded_on.month, recorded_on.day):
        years -= 1
    return min(age_years + max(years, 0), 100)


def calculate(ctx: CalcContext, profile: ProfileInputs) -> Targets:
    nutrition_targets = nutrition.calculate(
        ctx,
        nutrition.NutritionInputs(
            sex=profile.sex,
            age_years=profile.age_years,
            height_cm=profile.height_cm,
            weight_kg=profile.weight_kg,
            activity_level=profile.activity_level,
            weight_goal=profile.weight_goal,
        ),
    )
    hydration_base = hydration.base_need(
        ctx,
        hydration.HydrationInputs(
            sex=profile.sex,
            age_years=profile.age_years,
            height_cm=float(profile.height_cm),
            weight_kg=float(profile.weight_kg),
            body_type=profile.body_type,
            activity_level=profile.activity_level,
        ),
    )
    return Targets(
        calc_version=ctx.calc_version,
        nutrition=nutrition_targets,
        hydration=hydration_base,
        healthy_weight_range_kg=nutrition.healthy_weight_range(ctx, profile.height_cm),
    )


def snapshot(profile: ProfileInputs, targets: Targets, ctx: CalcContext) -> dict[str, Any]:
    """JSON object for app.pr_upsert_target_snapshot (keys are the table's columns)."""
    n = targets.nutrition
    activity = ctx.activity_levels[profile.activity_level]
    return {
        "calc_version": targets.calc_version,
        "inputs": {
            "sex": profile.sex,
            "age_years": profile.age_years,
            "height_cm": float(profile.height_cm),
            "weight_kg": float(profile.weight_kg),
            "activity_level": profile.activity_level,
            "weight_goal": profile.weight_goal,
            "body_type": profile.body_type,
            "tdee_multiplier": float(activity.tdee_multiplier),
            "activity_number": activity.activity_number,
            "temperature_c": targets.hydration.temperature_c,
        },
        "bmi": float(n.bmi),
        "bmi_category": n.bmi_category,
        "bmr_kcal": n.bmr_kcal,
        "tdee_kcal": n.tdee_kcal,
        "goal_delta_kcal": n.goal_delta_kcal,
        "calculated_target_kcal": n.calculated_target_kcal,
        "base_target_kcal": n.base_target_kcal,
        "safety_override": n.safety_override,
        "carbs_g": n.carbs_g,
        "fat_g": n.fat_g,
        "protein_g": n.protein_g,
        "lean_body_weight_kg": float(half_up_float(targets.hydration.lean_body_weight_kg, 2)),
        "water_movement_ml": float(half_up_float(targets.hydration.water_movement_ml, 1)),
        "base_water_need_ml": targets.water_need_ml,
    }
