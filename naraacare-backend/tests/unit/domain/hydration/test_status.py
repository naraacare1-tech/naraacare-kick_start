"""Hydration status engine against doc 06 sections 3.7-3.11 (Kompal and Sahil timelines)."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest

from app.domain.hydration import status as engine
from app.domain.hydration.calculator import HydrationInputs
from tests.calc_seed import seed_context

CTX = seed_context()
IST = ZoneInfo("Asia/Kolkata")
DAY = date(2026, 11, 2)


def at(hh: int, mm: int = 0, day: date = DAY) -> datetime:
    return datetime.combine(day, time(hh, mm), IST)


KOMPAL = HydrationInputs(
    sex="female",
    age_years=32,
    height_cm=162,
    weight_kg=65,
    body_type="endomorph",
    activity_level="sedentary",
)
SAHIL = HydrationInputs(
    sex="male",
    age_years=28,
    height_cm=175,
    weight_kg=80,
    body_type="mesomorph",
    activity_level="very_active",
)


def day_of(
    profile: HydrationInputs = KOMPAL, *, advanced: bool = False, **kw: object
) -> engine.DayInputs:
    base: dict[str, object] = {
        "day": DAY,
        "today": DAY,
        "timezone": IST,
        "wake": time(7),
        "sleep_start": time(23),
        "advanced": advanced,
        "calc_version": "2026.1",
        "profile": profile,
    }
    base.update(kw)
    return engine.DayInputs(**base)  # type: ignore[arg-type]


def water(hh: int, mm: int, ml: float) -> engine.Fill:
    return engine.Fill(at(hh, mm), ml)


def test_kompal_wakes_at_81_7_percent() -> None:
    s = engine.compute(CTX, day_of(), at(7))
    assert round(s.balance_ml, 1) == -238.3
    assert round(s.level_pct, 1) == 81.7
    assert round(s.tank_ml) == 1300
    assert round(s.daily_goal_ml) == 3053
    assert s.band == "well" and s.state == "empty"


@pytest.mark.parametrize(
    ("moment", "drinks", "balance", "level"),
    [
        (at(7, 30), [], -326.3, 74.9),
        (at(7, 30), [water(7, 30, 100)], -226.3, 82.6),
        (at(9, 30), [water(7, 30, 100)], -578.2, 55.5),
        (at(9, 30), [water(7, 30, 100), water(9, 30, 200)], -378.2, 70.9),
    ],
)
def test_kompal_timeline(
    moment: datetime, drinks: list[engine.Fill], balance: float, level: float
) -> None:
    s = engine.compute(CTX, day_of(drinks=drinks), moment)
    assert round(s.balance_ml, 1) == balance
    assert round(s.level_pct, 1) == level


def test_kompal_left_to_drink_and_drain_rate() -> None:
    s = engine.compute(CTX, day_of(drinks=[water(7, 30, 100), water(9, 30, 200)]), at(9, 30))
    assert round(s.left_to_drink_ml) == 2753
    assert round(s.drain_ml_per_hour, 1) == 175.9
    assert round(s.drain_ml_per_hour / s.tank_ml * 100, 1) == 13.5
    assert s.state == "in_progress" and round(s.effective_intake_ml) == 300
    assert round(s.consumed_pct, 1) == 9.8


def test_star_temperature_changes_need_and_applies_from_its_time() -> None:
    hot = day_of(advanced=True, temperatures=[(at(9), 35.0)])
    assert round(engine.compute(CTX, hot, at(8)).daily_goal_ml) == 3053
    s = engine.compute(CTX, hot, at(10))
    assert round(s.daily_goal_ml) == 3844
    assert s.temperature_c == 35 and s.temperature_set_at == at(9) and not s.temperature_stale
    plain = engine.compute(CTX, day_of(advanced=True), at(10))
    assert s.balance_ml < plain.balance_ml  # the hour after 09:00 drained faster
    assert plain.temperature_stale  # STAR without a temperature today (OQ-19 nudge)
    assert (
        round(
            engine.compute(
                CTX, day_of(advanced=True, temperatures=[(at(9), 22.0)]), at(10)
            ).daily_goal_ml
        )
        == 2880
    )


def test_standard_ignores_temperature_and_workouts() -> None:
    kept = day_of(temperatures=[(at(9), 35.0)], workouts=[(at(8), 500.0)])
    s = engine.compute(CTX, kept, at(10))
    assert round(s.daily_goal_ml) == 3053
    assert s.temperature_c == 25 and not s.temperature_stale and s.workout_sweat_ml == 0


def test_sahil_run_drops_62_5_percent_at_once() -> None:
    day = day_of(SAHIL, advanced=True, temperatures=[(at(7), 30.0)], workouts=[(at(12), 1000.0)])
    before = engine.compute(CTX, day, at(12) - timedelta(microseconds=1))
    after = engine.compute(CTX, day, at(12))
    assert round(after.tank_ml) == 1600
    assert round(before.level_pct - after.level_pct, 1) == 62.5 or after.level_pct == 0
    assert round(after.daily_goal_ml) == 5047
    assert round(after.workout_sweat_ml) == 1000


def test_balance_capped_at_plus_300_and_level_clamped() -> None:
    s = engine.compute(CTX, day_of(drinks=[water(7, 0, 3000)]), at(7))
    assert s.balance_ml == 300 and s.level_pct == 100
    empty = engine.compute(CTX, day_of(), at(22, 59))
    assert empty.level_pct == 0 and empty.band == "critical"


def test_meal_credit_is_a_fifth_of_need_over_three() -> None:
    s = engine.compute(CTX, day_of(meal_credits=[at(8)]), at(8))
    assert round(s.food_water_ml) == 204
    assert s.state == "empty"  # food water is not part of the headline (OQ-17)


@pytest.mark.parametrize(
    ("level", "band"),
    [
        (100, "well"),
        (80, "well"),
        (79.9, "drink_soon"),
        (50, "drink_soon"),
        (49.9, "low"),
        (20, "low"),
        (19.9, "critical"),
    ],
)
def test_band_boundaries(level: float, band: str) -> None:
    assert engine._band(CTX, level) == band


@pytest.mark.parametrize(
    ("ml", "state", "caution"),
    [
        (3054, "goal_completed", False),  # the goal is 3,053.25 mL at full precision
        (3358, "goal_completed", False),
        (3359, "above_goal", False),
        (4580, "above_goal", True),
    ],
)
def test_headline_states(ml: float, state: str, caution: bool) -> None:
    drinks = [water(8, 0, ml)]
    s = engine.compute(CTX, day_of(drinks=drinks), at(12))
    assert s.state == state and s.overhydration_caution is caution
    assert s.goal_completed


def test_day_ending_soon_only_today_and_within_three_hours() -> None:
    drinks = [water(8, 0, 500)]
    assert engine.compute(CTX, day_of(drinks=drinks), at(19, 59)).state == "in_progress"
    assert engine.compute(CTX, day_of(drinks=drinks), at(20, 0)).state == "day_ending_soon"
    past = day_of(drinks=[water(8, 0, 500)], today=DAY + timedelta(days=1))
    s = engine.compute(CTX, past, at(12))
    assert s.state == "in_progress" and round(s.left_to_drink_ml) == round(-s.balance_ml)


def test_before_wake_counts_from_wake_and_bedtime_after_midnight() -> None:
    early = day_of(drinks=[water(6, 0, 200)])
    assert round(engine.compute(CTX, early, at(5)).balance_ml, 1) == -38.3
    late = day_of(sleep_start=time(1), wake=time(9))
    s = engine.compute(CTX, late, at(9))
    assert round(s.balance_ml, 1) == -238.3  # 8 h of sleep either way


def test_from_db_and_json() -> None:
    raw = {
        "date": "2026-11-02",
        "today": "2026-11-02",
        "timezone": "Asia/Kolkata",
        "wake_local": "07:00",
        "sleep_start_local": "23:00",
        "temperature_unit": "f",
        "tier": "star",
        "advanced": True,
        "calc_version": "2026.1",
        "inputs": {
            "sex": "female",
            "age_years": 32,
            "height_cm": 162,
            "weight_kg": 65,
            "body_type": "endomorph",
            "activity_level": "sedentary",
        },
        "temperatures": [{"c": 30.5, "from": "2026-11-02T08:00:00+05:30"}],
        "intakes": [{"at": "2026-11-02T07:30:00+05:30", "effective_ml": 100.0, "volume_ml": 100}],
        "workouts": [{"at": "2026-11-02T08:30:00+05:30", "sweat_ml": 243.8}],
        "meal_credits": ["2026-11-02T08:00:00+05:30"],
        "goal_completed_at": None,
    }
    day = engine.DayInputs.from_db(raw)
    out = engine.to_json(engine.compute(CTX, day, at(9)), day.temperature_unit)
    assert out["temperature"] == {
        "c": 30.5,
        "unit": "f",
        "set_at": "2026-11-02T08:00:00+05:30",
        "stale": False,
    }
    assert out["state"] == "in_progress" and out["effective_intake_ml"] == 100
    assert out["workout_sweat_ml"] == 244 and isinstance(out["daily_goal_ml"], int)
    assert set(out["breakdown"]) == {"insensible_ml", "stool_ml", "sweat_ml", "urine_ml"}
