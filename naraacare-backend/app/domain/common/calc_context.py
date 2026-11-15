"""Calculation constants and numeric reference rows (doc 06), loaded from ``ref.fn_calc_context()``.

The calculators never hard-code a constant: they read it from this context, which carries the
``calc_version`` it came from. Snapshots store that version so past days stay reproducible.
"""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass
from decimal import Decimal
from typing import Any


class CalcContextError(RuntimeError):
    """The database returned an incomplete calculation context (a deployment problem)."""


@dataclass(frozen=True, slots=True)
class ActivityLevel:
    tdee_multiplier: Decimal
    activity_number: float
    athlete_bonus_ml: float


@dataclass(frozen=True, slots=True)
class WeightGoal:
    kcal_delta: int
    direction: str
    display_order: int
    offered: bool = True  # in the goal picker / accepted as a new choice (owner 2026-11-07)


@dataclass(frozen=True, slots=True)
class BmiCategory:
    code: str
    min_bmi: Decimal
    max_bmi_exclusive: Decimal | None
    blocked_goal_codes: frozenset[str]


@dataclass(frozen=True, slots=True)
class CalcContext:
    calc_version: str
    constants: Mapping[str, Decimal]
    activity_levels: Mapping[str, ActivityLevel]
    body_types: Mapping[str, Decimal]
    weight_goals: Mapping[str, WeightGoal]
    bmi_categories: tuple[BmiCategory, ...]
    medical_condition_codes: frozenset[str]
    avatar_codes: frozenset[str]

    def const(self, key: str) -> Decimal:
        try:
            return self.constants[key]
        except KeyError:
            raise CalcContextError(f"calc constant missing: {key}") from None

    def f(self, key: str) -> float:
        return float(self.const(key))

    @classmethod
    def from_db(cls, raw: object) -> CalcContext:
        """Parse the jsonb (asyncpg returns it as text) with exact decimals."""
        data: dict[str, Any] = (
            json.loads(raw, parse_float=Decimal) if isinstance(raw, str | bytes) else dict(raw)  # type: ignore[call-overload]
        )

        def dec(value: object) -> Decimal:
            return value if isinstance(value, Decimal) else Decimal(str(value))

        try:
            return cls(
                calc_version=str(data["calc_version"]),
                constants={k: dec(v) for k, v in data["constants"].items()},
                activity_levels={
                    code: ActivityLevel(
                        tdee_multiplier=dec(v["tdee_multiplier"]),
                        activity_number=float(v["activity_number"]),
                        athlete_bonus_ml=float(v["athlete_bonus_ml"]),
                    )
                    for code, v in data["activity_levels"].items()
                },
                body_types={code: dec(v) for code, v in data["body_types"].items()},
                weight_goals={
                    code: WeightGoal(
                        kcal_delta=int(v["kcal_delta"]),
                        direction=str(v["direction"]),
                        display_order=int(v["display_order"]),
                        offered=bool(v.get("offered", True)),
                    )
                    for code, v in data["weight_goals"].items()
                },
                bmi_categories=tuple(
                    BmiCategory(
                        code=str(c["code"]),
                        min_bmi=dec(c["min_bmi"]),
                        max_bmi_exclusive=None
                        if c["max_bmi_exclusive"] is None
                        else dec(c["max_bmi_exclusive"]),
                        blocked_goal_codes=frozenset(c["blocked_goal_codes"]),
                    )
                    for c in data["bmi_categories"]
                ),
                medical_condition_codes=frozenset(data["medical_condition_codes"]),
                avatar_codes=frozenset(data["avatar_codes"]),
            )
        except (KeyError, TypeError, ValueError, ArithmeticError):
            raise CalcContextError("calculation context is incomplete") from None
