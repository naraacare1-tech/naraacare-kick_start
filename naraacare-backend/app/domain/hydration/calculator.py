"""Daily water need (doc 06 section 3, Yamada et al. 2022). Full precision, rounded only for
display.

Session 05 needs the base need (default temperature, no workouts) for the target snapshot; the
tank, drains and fills arrive with hydration logging in Session 09.
"""

from __future__ import annotations

from dataclasses import dataclass

from app.domain.common.calc_context import CalcContext


@dataclass(frozen=True, slots=True)
class HydrationInputs:
    sex: str
    age_years: int
    height_cm: float
    weight_kg: float
    body_type: str
    activity_level: str


@dataclass(frozen=True, slots=True)
class HydrationBase:
    lean_body_weight_kg: float
    water_movement_ml: float
    need_before_workouts_ml: float
    daily_need_ml: float  # clamped to the product limits
    temperature_c: float


def lean_body_weight(ctx: CalcContext, inputs: HydrationInputs) -> float:
    """Boer 1984 x body-type factor (doc 06 section 3.2)."""
    sex = "male" if inputs.sex == "male" else "female"
    lbw = (
        ctx.f(f"hyd.lbw.{sex}.weight_coeff") * inputs.weight_kg
        + ctx.f(f"hyd.lbw.{sex}.height_coeff") * inputs.height_cm
        + ctx.f(f"hyd.lbw.{sex}.constant")
    )
    return lbw * float(ctx.body_types[inputs.body_type])


def water_movement(ctx: CalcContext, inputs: HydrationInputs, lbw: float, temp_c: float) -> float:
    """Daily water turnover TWT in mL (doc 06 section 3.3)."""
    activity = ctx.activity_levels[inputs.activity_level]
    age = inputs.age_years
    age_effect = ctx.f("hyd.twt.age_linear") * age + ctx.f("hyd.twt.age_quadratic") * age**2
    temp_effect = (
        ctx.f("hyd.twt.temp_quadratic") * temp_c**2 + ctx.f("hyd.twt.temp_linear") * temp_c
    )
    return (
        ctx.f("hyd.twt.activity_coeff") * activity.activity_number
        + ctx.f("hyd.twt.lbw_coeff") * lbw
        + activity.athlete_bonus_ml
        + age_effect
        + temp_effect
        + ctx.f("hyd.twt.constant")
    )


def clamp_need(ctx: CalcContext, need_ml: float) -> float:
    return min(max(need_ml, ctx.f("hyd.need.min_ml")), ctx.f("hyd.need.max_ml"))


def base_need(
    ctx: CalcContext,
    inputs: HydrationInputs,
    *,
    temp_c: float | None = None,
    workout_sweat_ml: float = 0.0,
) -> HydrationBase:
    """Need = 0.85 x TWT (+ workout sweat), clamped (doc 06 section 3.4). Default 25 C."""
    temperature = ctx.f("hyd.temp.default_c") if temp_c is None else temp_c
    lbw = lean_body_weight(ctx, inputs)
    twt = water_movement(ctx, inputs, lbw, temperature)
    before = ctx.f("hyd.need.drink_food_share") * twt
    return HydrationBase(
        lean_body_weight_kg=lbw,
        water_movement_ml=twt,
        need_before_workouts_ml=before,
        daily_need_ml=clamp_need(ctx, before + workout_sweat_ml),
        temperature_c=temperature,
    )
