"""A copy of the calc_version 2026.2 reference data (naraacare-database seed/R__10, R__11) for unit
tests of the calculators. ``tests/integration/test_profile_flow.py`` compares it with
``ref.fn_calc_context()`` from a real database, so the two cannot drift apart unnoticed."""

from __future__ import annotations

import json
from typing import Any

from app.domain.common.calc_context import CalcContext

SEED: dict[str, Any] = {
    "calc_version": "2026.2",
    "constants": {
        "nutr.bmr.weight_coeff": 10,
        "nutr.bmr.height_coeff": 6.25,
        "nutr.bmr.age_coeff": 5,
        "nutr.bmr.male_offset": 5,
        "nutr.bmr.female_offset": -161,
        "nutr.kcal_per_kg_fat": 7700,
        "nutr.floor.female_kcal": 1200,
        "nutr.floor.male_kcal": 1500,
        "nutr.macro.carbs_share": 0.55,
        "nutr.macro.fat_share": 0.25,
        "nutr.macro.protein_share": 0.20,
        "nutr.macro.carbs_kcal_per_g": 4,
        "nutr.macro.fat_kcal_per_g": 9,
        "nutr.macro.protein_kcal_per_g": 4,
        "hyd.lbw.male.weight_coeff": 0.407,
        "hyd.lbw.male.height_coeff": 0.267,
        "hyd.lbw.male.constant": -19.2,
        "hyd.lbw.female.weight_coeff": 0.252,
        "hyd.lbw.female.height_coeff": 0.473,
        "hyd.lbw.female.constant": -48.3,
        "hyd.twt.activity_coeff": 861.9,
        "hyd.twt.lbw_coeff": 37.34,
        "hyd.twt.age_linear": 29.42,
        "hyd.twt.age_quadratic": -0.3625,
        "hyd.twt.temp_quadratic": 1.937,
        "hyd.twt.temp_linear": -23.15,
        "hyd.twt.constant": -665.4,
        "hyd.need.drink_food_share": 0.85,
        "hyd.need.min_ml": 1500,
        "hyd.need.max_ml": 6000,
        "hyd.temp.default_c": 25,
        "hyd.temp.min_c": 15,
        "hyd.temp.max_c": 40,
        "hyd.loss.insensible_ml_per_kg_day": 11,
        "hyd.loss.stool_ml_per_day": 150,
        "hyd.loss.everyday_sweat_ml": 100,
        "hyd.loss.heat_sweat_reference_ml": 632,
        "hyd.loss.urine_min_ml": 500,
        "hyd.sleep.default_hours": 8,
        "hyd.food.share_of_need": 0.20,
        "hyd.food.meals_per_day": 3,
        "hyd.tank.body_weight_share": 0.02,
        "hyd.tank.extra_allowance_ml": 300,
        "hyd.custom_drink.default_factor": 0.85,
        "hyd.quick_add_ml": 100,
        "hyd.band.well_from_pct": 80,
        "hyd.band.drink_soon_from_pct": 50,
        "hyd.band.low_from_pct": 20,
        "hyd.state.goal_completed_max_ratio": 1.10,
        "hyd.state.overhydration_ratio": 1.5,
        "hyd.state.day_ending_soon_hours": 3,
    },
    "activity_levels": {
        # 2026-11 MVP document (owner 2026-11-24): standard TDEE multipliers, four water levels.
        "sedentary": {"tdee_multiplier": 1.2, "activity_number": 1.55, "athlete_bonus_ml": 0},
        "lightly_active": {
            "tdee_multiplier": 1.375,
            "activity_number": 1.70,
            "athlete_bonus_ml": 0,
        },
        "moderately_active": {
            "tdee_multiplier": 1.55,
            "activity_number": 1.85,
            "athlete_bonus_ml": 0,
        },
        "very_active": {
            "tdee_multiplier": 1.725,
            "activity_number": 2.00,
            "athlete_bonus_ml": 699.7,
        },
    },
    "body_types": {"ectomorph": 0.97, "mesomorph": 1.00, "endomorph": 1.03},
    "weight_goals": {
        "aggressive_loss": {"kcal_delta": -1000, "direction": "loss", "display_order": 1},
        "moderate_loss": {"kcal_delta": -750, "direction": "loss", "display_order": 2},
        "standard_loss": {"kcal_delta": -500, "direction": "loss", "display_order": 3},
        "mild_loss": {"kcal_delta": -250, "direction": "loss", "display_order": 4},
        "maintain": {"kcal_delta": 0, "direction": "maintain", "display_order": 5},
        "mild_gain": {"kcal_delta": 250, "direction": "gain", "display_order": 6},
        "standard_gain": {"kcal_delta": 500, "direction": "gain", "display_order": 7},
        "aggressive_gain": {"kcal_delta": 750, "direction": "gain", "display_order": 8},
    },
    "bmi_categories": [
        {
            "code": "underweight",
            "min_bmi": 0,
            "max_bmi_exclusive": 18.5,
            "blocked_goal_codes": [
                "aggressive_loss",
                "moderate_loss",
                "standard_loss",
                "mild_loss",
            ],
        },
        {
            "code": "normal",
            "min_bmi": 18.5,
            "max_bmi_exclusive": 25.0,
            "blocked_goal_codes": ["aggressive_loss"],
        },
        {
            "code": "overweight_obese",
            "min_bmi": 25.0,
            "max_bmi_exclusive": None,
            "blocked_goal_codes": [],
        },
    ],
    "medical_condition_codes": ["none", "diabetes", "hypertension", "allergy_peanut"],
    "avatar_codes": [
        "female_ectomorph",
        "female_mesomorph",
        "female_endomorph",
        "male_ectomorph",
        "male_mesomorph",
        "male_endomorph",
    ],
}


def seed_context() -> CalcContext:
    return CalcContext.from_db(json.dumps(SEED))
