"""Meal type suggested from the local time (doc 06 section 2.11, OQ-18); the user can change it.

05:00-10:59 breakfast, 11:00-15:59 lunch, 16:00-18:59 snack, 19:00-04:59 dinner.
"""

from __future__ import annotations

from datetime import time

MEAL_TYPES = ("breakfast", "lunch", "dinner", "snack")
# (first hour, meal type) in order; before the first and after the last band it is dinner.
_BANDS = ((5, "breakfast"), (11, "lunch"), (16, "snack"), (19, "dinner"))


def suggest_meal_type(local: time) -> str:
    current = "dinner"
    for start, meal_type in _BANDS:
        if local.hour >= start:
            current = meal_type
    return current
