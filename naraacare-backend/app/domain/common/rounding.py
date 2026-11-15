"""Rounding rules (OQ-21): nutrition rounds half-up after each step; hydration rounds only for
display."""

from __future__ import annotations

from decimal import ROUND_HALF_UP, Decimal


def half_up(value: Decimal, places: int = 0) -> Decimal:
    """Half-up (not banker's) rounding: 61.5 -> 62, 1713.6 -> 1714, 24.95 -> 25.0 at 1 place."""
    return value.quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP)


def half_up_int(value: Decimal) -> int:
    return int(half_up(value))


def half_up_float(value: float, places: int = 0) -> Decimal:
    """Display rounding of a float computed at full precision. Binary noise is removed at 9 decimal
    places first, so 60.085 (stored as 60.084999...) rounds to 60.09 like the DOC examples."""
    return half_up(Decimal(f"{value:.9f}"), places)
