"""Nutrient display rules (doc 06 section 2.10, doc 04 section 3 ``nutrients_17``).

The database stores and sums nutrients at 3 decimals (``nutrition.fn_item_nutrients``, the only
nutrient maths); this module only filters by tier and rounds for display:
* kcal -> integer; g -> 1 decimal; mg / mcg -> integer (half-up, OQ-21).
* STANDARD sees the nutrients whose ``tier_required`` is ``standard`` (6) and the count of the
  rest (``locked_nutrients_count``, 11); STAR sees all 17. The tier of each nutrient comes from
  ``ref.nutrient`` through the bootstrap payload, so the split lives in one place.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from app.domain.common.rounding import half_up

STAR = "star"


@dataclass(frozen=True, slots=True)
class Nutrient:
    code: str
    label: str
    unit: str  # kcal | g | mg | mcg
    tier_required: str  # standard | star


def nutrients_from_bootstrap(payload: Mapping[str, Any]) -> tuple[Nutrient, ...]:
    """The ordered nutrient list from the bootstrap payload (``ref.nutrient``)."""
    return tuple(
        Nutrient(str(n["code"]), str(n["label"]), str(n["unit"]), str(n["tier_required"]))
        for n in payload.get("nutrients", [])
    )


def display_value(unit: str, value: Decimal | float | str | None) -> Decimal | None:
    """Rounded for display: kcal and mg/mcg to integers, g to 1 decimal. ``None`` stays unknown."""
    if value is None:
        return None
    amount = value if isinstance(value, Decimal) else Decimal(str(value))
    return half_up(amount, 1 if unit == "g" else 0)


@dataclass(frozen=True, slots=True)
class NutrientView:
    values: list[dict[str, Any]]  # [{code, label, unit, value}] in display order
    locked_nutrients_count: int


def visible(
    nutrients: Sequence[Nutrient], tier: str, raw: Mapping[str, Any] | None
) -> NutrientView:
    """Values the tier may see, rounded, in ``ref.nutrient`` order; missing values are ``None``
    (unknown, e.g. an Open Food Facts product without vitamin C)."""
    raw = raw or {}
    shown: list[dict[str, Any]] = []
    locked = 0
    for n in nutrients:
        if n.tier_required == STAR and tier != STAR:
            locked += 1
            continue
        shown.append(
            {
                "code": n.code,
                "label": n.label,
                "unit": n.unit,
                "value": display_value(n.unit, raw.get(n.code)),
            }
        )
    return NutrientView(shown, locked)
