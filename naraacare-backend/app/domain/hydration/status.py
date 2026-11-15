"""Hydration status engine (doc 06 sections 3.4-3.8, OQ-04, OQ-17, OQ-19, OQ-55).

A pure function of one local day's inputs (``hydration.fn_day_inputs``) and a moment ``at``. Full
precision internally; values are rounded only in the returned representation (OQ-21).

* The day starts at the user's wake time with the overnight loss already drained; until bedtime the
  tank drains at the awake rate of the temperature in force (piecewise: a temperature change applies
  from that moment, hours already passed keep the old rate); after bedtime it drains at the sleep
  rate. Entries logged before wake time count at wake time.
* Fills: drinks add their effective mL (snapshot factor), each meal with a food credit adds
  ``0.20 x daily need / 3``; the balance never exceeds the extra-water allowance (+300 mL).
* STAR (``advanced``) only: temperatures (default 25 C otherwise) and workouts (sweat is drained at
  once and added to the daily need). STANDARD rows kept from a STAR period are ignored.
* Headline (OQ-17): effective drink intake today vs the daily goal; the avatar fill is the tank
  level.
"""

from __future__ import annotations

import itertools
from collections.abc import Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Any
from zoneinfo import ZoneInfo

from app.domain.common.calc_context import CalcContext
from app.domain.common.rounding import half_up_float
from app.domain.hydration.calculator import HydrationInputs, base_need, clamp_need

HOUR = timedelta(hours=1)


@dataclass(frozen=True, slots=True)
class Fill:
    at: datetime
    effective_ml: float


@dataclass(frozen=True, slots=True)
class DayInputs:
    day: date
    today: date
    timezone: ZoneInfo
    wake: time
    sleep_start: time
    advanced: bool
    calc_version: str
    profile: HydrationInputs
    temperatures: Sequence[tuple[datetime, float]] = ()
    drinks: Sequence[Fill] = ()
    workouts: Sequence[tuple[datetime, float]] = ()  # (performed_at, sweat_ml)
    meal_credits: Sequence[datetime] = ()
    goal_completed_at: datetime | None = None
    temperature_unit: str = "c"

    @classmethod
    def from_db(cls, raw: Mapping[str, Any]) -> DayInputs:
        """Parse the jsonb of ``hydration.fn_day_inputs``."""
        inputs = raw["inputs"]

        def ts(value: object) -> datetime:
            return datetime.fromisoformat(str(value))

        return cls(
            day=date.fromisoformat(str(raw["date"])),
            today=date.fromisoformat(str(raw["today"])),
            timezone=ZoneInfo(str(raw["timezone"])),
            wake=time.fromisoformat(str(raw["wake_local"])),
            sleep_start=time.fromisoformat(str(raw["sleep_start_local"])),
            advanced=bool(raw["advanced"]),
            calc_version=str(raw["calc_version"]),
            profile=HydrationInputs(
                sex=str(inputs["sex"]),
                age_years=int(inputs["age_years"]),
                height_cm=float(inputs["height_cm"]),
                weight_kg=float(inputs["weight_kg"]),
                body_type=str(inputs["body_type"]),
                activity_level=str(inputs["activity_level"]),
            ),
            temperatures=tuple((ts(t["from"]), float(t["c"])) for t in raw["temperatures"]),
            drinks=tuple(Fill(ts(i["at"]), float(i["effective_ml"])) for i in raw["intakes"]),
            workouts=tuple((ts(w["at"]), float(w["sweat_ml"])) for w in raw["workouts"]),
            meal_credits=tuple(ts(m) for m in raw["meal_credits"]),
            goal_completed_at=ts(raw["goal_completed_at"])
            if raw.get("goal_completed_at")
            else None,
            temperature_unit=str(raw.get("temperature_unit") or "c"),
        )


@dataclass(slots=True)
class HydrationStatus:
    level_pct: float
    band: str
    balance_ml: float
    tank_ml: float
    daily_goal_ml: float
    effective_intake_ml: float
    consumed_pct: float
    left_to_drink_ml: float
    state: str
    overhydration_caution: bool
    temperature_c: float
    temperature_set_at: datetime | None
    temperature_stale: bool
    food_water_ml: float
    workout_sweat_ml: float
    drain_ml_per_hour: float
    goal_completed: bool
    calc_version: str
    breakdown: dict[str, float] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class _Day:
    wake: datetime
    bed: datetime
    awake_h: float
    sleep_h: float


def _day_window(day: DayInputs) -> _Day:
    wake = datetime.combine(day.day, day.wake, day.timezone)
    bed = datetime.combine(day.day, day.sleep_start, day.timezone)
    if bed <= wake:
        bed += timedelta(days=1)
    awake_h = (bed - wake) / HOUR
    return _Day(wake=wake, bed=bed, awake_h=awake_h, sleep_h=24.0 - awake_h)


class _Model:
    """Rates for one day; temperature-dependent values are cached per temperature."""

    def __init__(self, ctx: CalcContext, day: DayInputs, window: _Day) -> None:
        self.ctx = ctx
        self.day = day
        self.window = window
        weight = day.profile.weight_kg
        self.sleep_rate = ctx.f("hyd.loss.insensible_ml_per_kg_day") * weight / 24.0
        self.overnight = self.sleep_rate * window.sleep_h
        self.tank = ctx.f("hyd.tank.body_weight_share") * weight * 1000.0
        self.cap = ctx.f("hyd.tank.extra_allowance_ml")
        self.default_c = ctx.f("hyd.temp.default_c")
        self._before: dict[float, float] = {}
        temps = sorted(day.temperatures) if day.advanced else []
        self.temps = [(max(at, window.wake), c) for at, c in temps]

    def need_before(self, temp_c: float) -> float:
        if temp_c not in self._before:
            self._before[temp_c] = base_need(
                self.ctx, self.day.profile, temp_c=temp_c
            ).need_before_workouts_ml
        return self._before[temp_c]

    def awake_rate(self, temp_c: float) -> float:
        return (self.need_before(temp_c) - self.overnight) / self.window.awake_h

    def temperature_at(self, at: datetime) -> float:
        current = self.default_c
        for start, c in self.temps:
            if start <= at:
                current = c
        return current

    def drain(self, start: datetime, end: datetime) -> float:
        """mL lost between two moments (piecewise over temperature changes and bedtime)."""
        if end <= start:
            return 0.0
        cuts = sorted({start, end, self.window.bed, *(t for t, _ in self.temps)})
        lost = 0.0
        for a, b in itertools.pairwise(cuts):
            if a < start or b > end:
                continue
            hours = (b - a) / HOUR
            rate = (
                self.sleep_rate if a >= self.window.bed else self.awake_rate(self.temperature_at(a))
            )
            lost += rate * hours
        return lost


def _band(ctx: CalcContext, level: float) -> str:
    if level >= ctx.f("hyd.band.well_from_pct"):
        return "well"
    if level >= ctx.f("hyd.band.drink_soon_from_pct"):
        return "drink_soon"
    if level >= ctx.f("hyd.band.low_from_pct"):
        return "low"
    return "critical"


def _breakdown(ctx: CalcContext, model: _Model, temp_c: float, sweat: float) -> dict[str, float]:
    """Display-only loss breakdown for the Info screen (doc 06 section 3.5)."""
    weight = model.day.profile.weight_kg
    need = model.need_before(temp_c)
    temp_effect = (
        ctx.f("hyd.twt.temp_quadratic") * temp_c**2 + ctx.f("hyd.twt.temp_linear") * temp_c
    )
    insensible = ctx.f("hyd.loss.insensible_ml_per_kg_day") * weight
    stool = ctx.f("hyd.loss.stool_ml_per_day")
    everyday_sweat = ctx.f("hyd.loss.everyday_sweat_ml") + max(
        0.0, temp_effect - ctx.f("hyd.loss.heat_sweat_reference_ml")
    )
    urine = max(ctx.f("hyd.loss.urine_min_ml"), need - insensible - stool - everyday_sweat)
    return {
        "insensible_ml": insensible,
        "stool_ml": stool,
        "sweat_ml": everyday_sweat + sweat,
        "urine_ml": urine,
    }


def compute(ctx: CalcContext, day: DayInputs, at: datetime) -> HydrationStatus:
    """Status of ``day`` at ``at`` (clamped to the day's wake time; past days end at bedtime)."""
    window = _day_window(day)
    model = _Model(ctx, day, window)
    if day.day < day.today:
        at = max(at, window.bed)
    now = max(at, window.wake)

    events: list[
        tuple[datetime, int, float]
    ] = []  # (time, kind, value); kind 0 drink, 1 meal, 2 workout
    events += [(max(d.at, window.wake), 0, d.effective_ml) for d in day.drinks if d.at <= now]
    events += [(max(m, window.wake), 1, 0.0) for m in day.meal_credits if m <= now]
    if day.advanced:
        events += [(max(w, window.wake), 2, s) for w, s in day.workouts if w <= now]
    events.sort(key=lambda e: (e[0], e[1]))

    share = ctx.f("hyd.food.share_of_need")
    meals_per_day = ctx.f("hyd.food.meals_per_day")
    balance = -model.overnight
    cursor = window.wake
    sweat = food = intake = 0.0
    for when, kind, value in events:
        balance -= model.drain(cursor, when)
        cursor = when
        if kind == 0:
            intake += value
            balance = min(balance + value, model.cap)
        elif kind == 1:
            credit = (
                share
                * clamp_need(ctx, model.need_before(model.temperature_at(when)) + sweat)
                / meals_per_day
            )
            food += credit
            balance = min(balance + credit, model.cap)
        else:
            sweat += value
            balance -= value
    balance -= model.drain(cursor, now)

    temp_now = model.temperature_at(now)
    goal = clamp_need(ctx, model.need_before(temp_now) + sweat)
    level = min(max(100.0 * (1.0 + balance / model.tank), 0.0), 100.0)
    awake_rate = model.awake_rate(temp_now)
    hours_left = max(0.0, (window.bed - now) / HOUR)
    left = max(0.0, -balance) + awake_rate * hours_left

    soon = ctx.f("hyd.state.day_ending_soon_hours")
    goal_ratio = intake / goal if goal else 0.0
    if intake <= 0:
        state = "empty"
    elif intake < goal:
        state = (
            "day_ending_soon" if day.day == day.today and 0 < hours_left <= soon else "in_progress"
        )
    elif goal_ratio <= ctx.f("hyd.state.goal_completed_max_ratio"):
        state = "goal_completed"
    else:
        state = "above_goal"
    caution = goal_ratio > ctx.f("hyd.state.overhydration_ratio") or intake > ctx.f(
        "hyd.need.max_ml"
    )

    set_at = max((t for t, _ in model.temps if t <= now), default=None)
    return HydrationStatus(
        level_pct=level,
        band=_band(ctx, level),
        balance_ml=balance,
        tank_ml=model.tank,
        daily_goal_ml=goal,
        effective_intake_ml=intake,
        consumed_pct=100.0 * goal_ratio,
        left_to_drink_ml=left,
        state=state,
        overhydration_caution=caution,
        temperature_c=temp_now,
        temperature_set_at=set_at,
        temperature_stale=day.advanced and day.day == day.today and set_at is None,
        food_water_ml=food,
        workout_sweat_ml=sweat,
        drain_ml_per_hour=awake_rate if now < window.bed else model.sleep_rate,
        goal_completed=intake >= goal,
        calc_version=day.calc_version,
        breakdown=_breakdown(ctx, model, temp_now, sweat),
    )


def _r1(value: float) -> float:
    return float(half_up_float(value, 1))


def _r0(value: float) -> int:
    return int(half_up_float(value))


def to_json(status: HydrationStatus, unit: str = "c") -> dict[str, Any]:
    """API representation (doc 04 section 2.5): mL as integers, percentages with one decimal."""
    temp = Decimal(str(status.temperature_c))
    return {
        "level_pct": _r1(status.level_pct),
        "band": status.band,
        "balance_ml": _r0(status.balance_ml),
        "tank_ml": _r0(status.tank_ml),
        "daily_goal_ml": _r0(status.daily_goal_ml),
        "effective_intake_ml": _r0(status.effective_intake_ml),
        "consumed_pct": _r1(status.consumed_pct),
        "left_to_drink_ml": _r0(status.left_to_drink_ml),
        "state": status.state,
        "overhydration_caution": status.overhydration_caution,
        "temperature": {
            "c": float(temp),
            "unit": unit,
            "set_at": status.temperature_set_at.isoformat() if status.temperature_set_at else None,
            "stale": status.temperature_stale,
        },
        "food_water_ml": _r0(status.food_water_ml),
        "workout_sweat_ml": _r0(status.workout_sweat_ml),
        "drain_ml_per_hour": _r1(status.drain_ml_per_hour),
        "breakdown": {k: _r0(v) for k, v in status.breakdown.items()},
        "calc_version": status.calc_version,
    }
