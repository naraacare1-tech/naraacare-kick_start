"""Energy avatar state (doc 06 section 2.8).

``fill_pct = food_kcal / effective_allowance x 100`` at 1 decimal (half-up), with half-open bands
so DOC's decimal gaps are closed (49.5 -> fueling, 99.9 -> energized):

    0            empty
    0 < x < 50   fueling
    50 <= x < 100  energized
    100 <= x <= 105  goal_met
    x > 105      overfilled
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal

from app.domain.common.rounding import half_up

EMPTY = "empty"
FUELING = "fueling"
ENERGIZED = "energized"
GOAL_MET = "goal_met"
OVERFILLED = "overfilled"
ENERGIZED_FROM = Decimal(50)
GOAL_MET_FROM = Decimal(100)
GOAL_MET_UNTIL = Decimal(105)


@dataclass(frozen=True, slots=True)
class AvatarState:
    fill_pct: Decimal
    state: str


def avatar_state(food_kcal: Decimal, effective_allowance_kcal: int | None) -> AvatarState:
    """No allowance yet (no target snapshot) counts as an empty avatar rather than an error."""
    if not effective_allowance_kcal or effective_allowance_kcal <= 0 or food_kcal <= 0:
        return AvatarState(Decimal("0.0"), EMPTY)
    pct = half_up(food_kcal / Decimal(effective_allowance_kcal) * 100, 1)
    if pct < ENERGIZED_FROM:
        state = FUELING
    elif pct < GOAL_MET_FROM:
        state = ENERGIZED
    elif pct <= GOAL_MET_UNTIL:
        state = GOAL_MET
    else:
        state = OVERFILLED
    return AvatarState(pct, state)
