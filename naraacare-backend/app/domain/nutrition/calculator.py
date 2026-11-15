"""Energy (nutrition) targets, doc 06 section 2, steps 1-6.

Order: BMR -> TDEE -> BMI guardrails -> goal adjustment -> safety floor -> macros. Every step is
rounded half-up to an integer (OQ-21), which reproduces the DOC examples exactly. Pure functions:
the constants come from ``CalcContext`` and nothing here does I/O.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from app.domain.common.calc_context import BmiCategory, CalcContext
from app.domain.common.rounding import half_up, half_up_int


class GoalNotAllowedError(ValueError):
    """The weight goal is blocked for the user's BMI category (doc 06 section 2.3)."""


@dataclass(frozen=True, slots=True)
class NutritionInputs:
    sex: str  # "female" | "male"
    age_years: int
    height_cm: Decimal
    weight_kg: Decimal
    activity_level: str
    weight_goal: str


@dataclass(frozen=True, slots=True)
class NutritionTargets:
    bmr_kcal: int
    tdee_kcal: int
    bmi: Decimal  # 1 decimal, for display and storage
    bmi_category: str
    goal_delta_kcal: int
    calculated_target_kcal: int
    base_target_kcal: int
    safety_override: bool
    carbs_g: int
    fat_g: int
    protein_g: int


def bmr(ctx: CalcContext, *, sex: str, weight_kg: Decimal, height_cm: Decimal, age: int) -> int:
    """Mifflin-St Jeor (step 1)."""
    offset = ctx.const("nutr.bmr.male_offset" if sex == "male" else "nutr.bmr.female_offset")
    value = (
        ctx.const("nutr.bmr.weight_coeff") * weight_kg
        + ctx.const("nutr.bmr.height_coeff") * height_cm
        - ctx.const("nutr.bmr.age_coeff") * age
        + offset
    )
    return half_up_int(value)


def tdee(ctx: CalcContext, bmr_kcal: int, activity_level: str) -> int:
    """BMR x activity multiplier (step 2; multipliers per OQ-12/OQ-13)."""
    return half_up_int(Decimal(bmr_kcal) * ctx.activity_levels[activity_level].tdee_multiplier)


def bmi_exact(weight_kg: Decimal, height_cm: Decimal) -> Decimal:
    height_m = height_cm / 100
    return weight_kg / (height_m * height_m)


def bmi_category(ctx: CalcContext, bmi_value: Decimal) -> BmiCategory:
    """Half-open intervals on the UNROUNDED BMI, so 24.95 is still Normal (doc 06 section 2.3)."""
    for category in ctx.bmi_categories:
        upper = category.max_bmi_exclusive
        if bmi_value >= category.min_bmi and (upper is None or bmi_value < upper):
            return category
    return ctx.bmi_categories[0]  # below every lower bound cannot happen (min 0); defensive


def allowed_goals(ctx: CalcContext, category: BmiCategory) -> list[str]:
    goals = sorted(ctx.weight_goals.items(), key=lambda item: item[1].display_order)
    return [code for code, g in goals if g.offered and code not in category.blocked_goal_codes]


def healthy_weight_range(ctx: CalcContext, height_cm: Decimal) -> tuple[int, int]:
    """[18.5 x h^2, 24.9 x h^2] kg, integers: the bounds of the 'normal' category (doc 06 2.3)."""
    normal = next(c for c in ctx.bmi_categories if c.code == "normal")
    upper_bmi = (normal.max_bmi_exclusive or Decimal("25.0")) - Decimal("0.1")
    h2 = (height_cm / 100) ** 2
    return half_up_int(normal.min_bmi * h2), half_up_int(upper_bmi * h2)


def calculate(ctx: CalcContext, inputs: NutritionInputs) -> NutritionTargets:
    bmr_kcal = bmr(
        ctx,
        sex=inputs.sex,
        weight_kg=inputs.weight_kg,
        height_cm=inputs.height_cm,
        age=inputs.age_years,
    )
    tdee_kcal = tdee(ctx, bmr_kcal, inputs.activity_level)
    bmi_value = bmi_exact(inputs.weight_kg, inputs.height_cm)
    category = bmi_category(ctx, bmi_value)
    if inputs.weight_goal in category.blocked_goal_codes:
        raise GoalNotAllowedError(inputs.weight_goal)
    delta = ctx.weight_goals[inputs.weight_goal].kcal_delta
    calculated = tdee_kcal + delta
    floor = half_up_int(
        ctx.const("nutr.floor.male_kcal" if inputs.sex == "male" else "nutr.floor.female_kcal")
    )
    base = max(calculated, floor)

    def grams(share_key: str, kcal_per_g_key: str) -> int:
        return half_up_int(Decimal(base) * ctx.const(share_key) / ctx.const(kcal_per_g_key))

    return NutritionTargets(
        bmr_kcal=bmr_kcal,
        tdee_kcal=tdee_kcal,
        bmi=half_up(bmi_value, 1),
        bmi_category=category.code,
        goal_delta_kcal=delta,
        calculated_target_kcal=calculated,
        base_target_kcal=base,
        safety_override=calculated < floor,
        carbs_g=grams("nutr.macro.carbs_share", "nutr.macro.carbs_kcal_per_g"),
        fat_g=grams("nutr.macro.fat_share", "nutr.macro.fat_kcal_per_g"),
        protein_g=grams("nutr.macro.protein_share", "nutr.macro.protein_kcal_per_g"),
    )
