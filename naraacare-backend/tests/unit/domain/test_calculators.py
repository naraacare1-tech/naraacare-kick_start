"""Doc 06 worked examples and boundaries for the nutrition and hydration calculators."""

from __future__ import annotations

from datetime import date
from decimal import Decimal

import pytest

from app.domain import targets
from app.domain.common.calc_context import CalcContext, CalcContextError
from app.domain.common.rounding import half_up, half_up_float
from app.domain.hydration import calculator as hydration
from app.domain.nutrition import calculator as nutrition
from tests.calc_seed import SEED, seed_context

CTX = seed_context()


def test_example_1_moderately_active_male_standard_gain() -> None:
    t = nutrition.calculate(
        CTX,
        nutrition.NutritionInputs(
            sex="male",
            age_years=30,
            height_cm=Decimal(180),
            weight_kg=Decimal(70),
            activity_level="moderately_active",
            weight_goal="standard_gain",
        ),
    )
    assert (t.bmr_kcal, t.tdee_kcal, t.bmi, t.bmi_category) == (
        1680,
        2604,
        Decimal("21.6"),
        "normal",
    )
    # 2026-11 MVP doc Example 1 (multiplier 1.55). The doc prints carbs 304 g, which is a typo:
    # 3104 x 0.55 / 4 = 427 g; its fat 86 g and protein 155 g match.
    assert (t.calculated_target_kcal, t.base_target_kcal, t.safety_override) == (3104, 3104, False)
    assert (t.carbs_g, t.fat_g, t.protein_g) == (427, 86, 155)


def test_example_2_sedentary_female_standard_loss_hits_the_safety_floor() -> None:
    t = nutrition.calculate(
        CTX,
        nutrition.NutritionInputs(
            sex="female",
            age_years=25,
            height_cm=Decimal(160),
            weight_kg=Decimal(65),
            activity_level="sedentary",
            weight_goal="standard_loss",
        ),
    )
    assert (t.bmr_kcal, t.tdee_kcal, t.bmi, t.bmi_category) == (
        1364,
        1637,
        Decimal("25.4"),
        "overweight_obese",
    )
    assert (t.calculated_target_kcal, t.base_target_kcal, t.safety_override) == (1137, 1200, True)
    assert (t.carbs_g, t.fat_g, t.protein_g) == (165, 33, 60)


@pytest.mark.parametrize(
    ("weight", "height", "category"),
    [
        (Decimal("59.93"), Decimal(180), "underweight"),  # 18.497
        (Decimal("59.94"), Decimal(180), "normal"),  # 18.500
        (Decimal("80.83"), Decimal(180), "normal"),  # 24.947: rounds to 24.9, Normal
        (Decimal("80.84"), Decimal(180), "normal"),  # 24.950: rounds to 25.0 but is < 25.0
        (Decimal("81.00"), Decimal(180), "overweight_obese"),  # 25.0
    ],
)
def test_bmi_category_uses_unrounded_half_open_intervals(
    weight: Decimal, height: Decimal, category: str
) -> None:
    assert nutrition.bmi_category(CTX, nutrition.bmi_exact(weight, height)).code == category


def test_blocked_goals_follow_the_bmi_guardrails() -> None:
    underweight = nutrition.bmi_category(CTX, Decimal(17))
    normal = nutrition.bmi_category(CTX, Decimal(22))
    obese = nutrition.bmi_category(CTX, Decimal(31))
    assert nutrition.allowed_goals(CTX, underweight) == [
        "maintain",
        "mild_gain",
        "standard_gain",
        "aggressive_gain",
    ]
    assert "aggressive_loss" not in nutrition.allowed_goals(CTX, normal)
    assert len(nutrition.allowed_goals(CTX, obese)) == 8
    with pytest.raises(nutrition.GoalNotAllowedError):
        nutrition.calculate(
            CTX,
            nutrition.NutritionInputs(
                sex="female",
                age_years=30,
                height_cm=Decimal(170),
                weight_kg=Decimal(50),  # BMI 17.3
                activity_level="sedentary",
                weight_goal="mild_loss",
            ),
        )


def test_male_floor_and_healthy_range() -> None:
    t = nutrition.calculate(
        CTX,
        nutrition.NutritionInputs(
            sex="male",
            age_years=90,
            height_cm=Decimal(150),
            weight_kg=Decimal(60),
            activity_level="sedentary",
            weight_goal="aggressive_loss",
        ),
    )
    assert t.base_target_kcal == 1500 and t.safety_override
    assert nutrition.healthy_weight_range(CTX, Decimal(160)) == (47, 64)


def _kompal() -> hydration.HydrationInputs:
    return hydration.HydrationInputs(
        sex="female",
        age_years=32,
        height_cm=162,
        weight_kg=65,
        body_type="endomorph",
        activity_level="sedentary",
    )


def test_kompal_base_need() -> None:
    base = hydration.base_need(CTX, _kompal())
    assert half_up_float(base.lean_body_weight_kg, 2) == Decimal("46.05")
    assert half_up_float(base.water_movement_ml) == 3592
    assert half_up_float(base.daily_need_ml) == 3053
    assert half_up_float(hydration.base_need(CTX, _kompal(), temp_c=22).daily_need_ml) == 2880
    assert half_up_float(hydration.base_need(CTX, _kompal(), temp_c=35).daily_need_ml) == 3844


def test_sahil_need_with_a_run() -> None:
    sahil = hydration.HydrationInputs(
        sex="male",
        age_years=28,
        height_cm=175,
        weight_kg=80,
        body_type="mesomorph",
        activity_level="very_active",
    )
    base = hydration.base_need(CTX, sahil, temp_c=30, workout_sweat_ml=12.5 * 80 * 1)
    # Very Active = 2.00 plus the 699.7 mL athlete term (2026-11 MVP doc). The doc's Sahil example
    # (5,047 mL) was still computed with the old 1.85 level.
    assert half_up_float(base.lean_body_weight_kg, 2) == Decimal("60.09")
    assert half_up_float(base.water_movement_ml) == 5590
    assert half_up_float(base.need_before_workouts_ml) == 4752
    assert half_up_float(base.daily_need_ml) == 5752


def test_need_is_clamped_to_product_limits() -> None:
    tiny = hydration.HydrationInputs(
        sex="female",
        age_years=100,
        height_cm=120,
        weight_kg=30,
        body_type="ectomorph",
        activity_level="sedentary",
    )
    assert hydration.base_need(CTX, tiny, temp_c=15).daily_need_ml == 1500
    big = hydration.base_need(CTX, _kompal(), workout_sweat_ml=10000)
    assert big.daily_need_ml == 6000


def test_snapshot_has_exactly_the_snapshot_columns() -> None:
    profile = targets.ProfileInputs(
        sex="male",
        age_years=30,
        height_cm=Decimal(180),
        weight_kg=Decimal(70),
        activity_level="moderately_active",
        weight_goal="standard_gain",
        body_type="mesomorph",
    )
    result = targets.calculate(CTX, profile)
    snap = targets.snapshot(profile, result, CTX)
    assert set(snap) == {
        "calc_version",
        "inputs",
        "bmi",
        "bmi_category",
        "bmr_kcal",
        "tdee_kcal",
        "goal_delta_kcal",
        "calculated_target_kcal",
        "base_target_kcal",
        "safety_override",
        "carbs_g",
        "fat_g",
        "protein_g",
        "lean_body_weight_kg",
        "water_movement_ml",
        "base_water_need_ml",
    }
    assert snap["base_target_kcal"] == 3104
    assert snap["base_water_need_ml"] == result.water_need_ml


@pytest.mark.parametrize(
    ("recorded", "today", "expected"),
    [
        (None, date(2030, 1, 1), 30),
        (date(2026, 10, 29), date(2027, 10, 28), 30),
        (date(2026, 10, 29), date(2027, 10, 29), 31),
        (date(2026, 10, 29), date(2096, 10, 29), 100),  # capped at the adult maximum
    ],
)
def test_current_age_counts_full_years_since_recorded(
    recorded: date | None, today: date, expected: int
) -> None:
    assert targets.current_age(30, recorded, today) == expected


def test_half_up_is_not_bankers_rounding() -> None:
    assert half_up(Decimal("61.5")) == 62
    assert half_up(Decimal("62.5")) == 63
    assert half_up(Decimal("24.95"), 1) == Decimal("25.0")


def test_incomplete_context_is_refused() -> None:
    broken = {k: v for k, v in SEED.items() if k != "constants"}
    with pytest.raises(CalcContextError):
        CalcContext.from_db(broken)
    with pytest.raises(CalcContextError):
        seed_context().const("nutr.unknown")
