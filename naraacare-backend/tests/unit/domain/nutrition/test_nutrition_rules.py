"""Avatar state, nutrient display/tiering and meal-type bands (doc 06 sections 2.8-2.11)."""

from __future__ import annotations

from datetime import time
from decimal import Decimal

import pytest

from app.domain.nutrition.avatar import avatar_state
from app.domain.nutrition.meal_type import suggest_meal_type
from app.domain.nutrition.nutrients import Nutrient, display_value, visible


@pytest.mark.parametrize(
    ("food", "allowance", "pct", "state"),
    [
        (Decimal(0), 2214, "0.0", "empty"),
        (Decimal(1), None, "0.0", "empty"),  # no target yet
        (Decimal(1107), 2214, "50.0", "energized"),  # DOC example 1
        (Decimal(1450), 1400, "103.6", "goal_met"),  # DOC example 2 (half-up, not truncated)
        (Decimal(1095), 2214, "49.5", "fueling"),  # half-open band closes DOC's gap
        (Decimal("2211.8"), 2214, "99.9", "energized"),
        (Decimal(2214), 2214, "100.0", "goal_met"),
        (Decimal("2324.7"), 2214, "105.0", "goal_met"),
        (Decimal(2326), 2214, "105.1", "overfilled"),
    ],
)
def test_avatar_bands(food: Decimal, allowance: int | None, pct: str, state: str) -> None:
    result = avatar_state(food, allowance)
    assert (str(result.fill_pct), result.state) == (pct, state)


def test_display_rounding_is_half_up_per_unit() -> None:
    assert display_value("kcal", Decimal("77.5")) == Decimal(78)
    assert display_value("g", Decimal("20.95")) == Decimal("21.0")
    assert display_value("mg", Decimal("6.5")) == Decimal(7)
    assert display_value("mcg", "0.4") == Decimal(0)
    assert display_value("g", None) is None


NUTRIENTS = (
    Nutrient("calories", "Calories", "kcal", "standard"),
    Nutrient("protein", "Protein", "g", "standard"),
    Nutrient("iron", "Iron", "mg", "star"),
    Nutrient("vitamin_c", "Vitamin C", "mg", "star"),
)


def test_standard_sees_standard_nutrients_and_the_locked_count() -> None:
    view = visible(NUTRIENTS, "standard", {"calories": "78.000", "protein": 0.45, "iron": 1})
    assert [v["code"] for v in view.values] == ["calories", "protein"]
    assert view.values[0]["value"] == Decimal(78)
    assert view.values[1]["value"] == Decimal("0.5")
    assert view.locked_nutrients_count == 2


def test_star_sees_everything_and_unknown_values_stay_unknown() -> None:
    view = visible(NUTRIENTS, "star", {"calories": 78})
    assert [v["code"] for v in view.values] == ["calories", "protein", "iron", "vitamin_c"]
    assert view.values[3]["value"] is None
    assert view.locked_nutrients_count == 0


@pytest.mark.parametrize(
    ("hour", "minute", "meal"),
    [
        (4, 59, "dinner"),
        (5, 0, "breakfast"),
        (10, 59, "breakfast"),
        (11, 0, "lunch"),
        (15, 59, "lunch"),
        (16, 0, "snack"),
        (18, 59, "snack"),
        (19, 0, "dinner"),
        (23, 30, "dinner"),
        (0, 0, "dinner"),
    ],
)
def test_meal_type_bands(hour: int, minute: int, meal: str) -> None:
    assert suggest_meal_type(time(hour, minute)) == meal
