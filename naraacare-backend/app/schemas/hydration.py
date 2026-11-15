"""Hydration, workouts, devices and notification settings requests (doc 04 sections 2.5 and 2.7).

Every string is a Safe* type or a closed ``Literal``; models forbid unknown fields and carry no
``user_id`` (the user is the token subject). Numbers carry the doc 06 ranges; the database checks
them again (CHECKs and procedures).
"""

from __future__ import annotations

from typing import Annotated, Literal, Self

from pydantic import AfterValidator, Field, model_validator

from app.core.security.validators import SafeAppVersion, SafeDeviceToken, SafeShortText60
from app.schemas.common import JsonDecimal, JsonTime, JsonUUID
from app.schemas.nutrition import JsonDateTime, _Model

DrinkCode = Literal["water", "tea", "milk", "coconut_water", "coffee", "juice", "beer"]
IntakeSource = Literal["swipe", "manual", "preset", "rin"]
WorkoutType = Literal["walking", "gym", "cycling", "swimming", "running", "trekking"]
ReminderType = Literal["hydration", "nutrition", "sleep", "daily_checkin", "health_profile"]

SWIPE_DOWN_ML = -100
MAX_DRINK_ML = 3000


def _volume(value: int) -> int:
    if value != SWIPE_DOWN_ML and not 1 <= value <= MAX_DRINK_ML:
        raise ValueError("volume must be 1..3000 mL (or -100 for a water swipe)")
    return value


Volume = Annotated[int, AfterValidator(_volume)]
EditVolume = Annotated[int, Field(ge=-100, le=3000), AfterValidator(_volume)]


class IntakeCreate(_Model):
    client_entry_id: JsonUUID
    logged_at: JsonDateTime
    drink_code: DrinkCode | None = None
    custom_drink_id: JsonUUID | None = None
    volume_ml: Annotated[Volume, Field(ge=-100, le=3000)]
    source: IntakeSource

    @model_validator(mode="after")
    def _one_drink(self) -> Self:
        if (self.drink_code is None) == (self.custom_drink_id is None):
            raise ValueError("exactly one of drink_code and custom_drink_id")
        if self.volume_ml == SWIPE_DOWN_ML and (
            self.source != "swipe" or self.drink_code != "water"
        ):
            raise ValueError("-100 mL is only a water swipe")
        return self


class IntakeUpdate(_Model):
    volume_ml: EditVolume | None = None
    drink_code: DrinkCode | None = None
    custom_drink_id: JsonUUID | None = None

    @model_validator(mode="after")
    def _at_most_one_drink(self) -> Self:
        if self.drink_code is not None and self.custom_drink_id is not None:
            raise ValueError("at most one of drink_code and custom_drink_id")
        return self


class TemperatureIn(_Model):
    temperature_c: Annotated[JsonDecimal, Field(ge=15, le=40, decimal_places=1)]


class CustomDrinkEstimateIn(_Model):
    name: SafeShortText60


class CustomDrinkIn(_Model):
    name: SafeShortText60
    hydration_factor: Annotated[JsonDecimal, Field(ge=0, le=1, decimal_places=3)]
    source: Literal["ai", "default", "user"] = "user"


class WorkoutCreate(_Model):
    client_entry_id: JsonUUID
    workout_type: WorkoutType
    duration_min: Annotated[int, Field(ge=1, le=600)]
    performed_at: JsonDateTime


class DeviceIn(_Model):
    installation_id: JsonUUID
    platform: Literal["android", "ios"]
    push_token: SafeDeviceToken
    app_version: SafeAppVersion


class NotificationPreferences(_Model):
    """The 12 toggles of Figma Notification Settings (doc 05 ``notify.notification_preference``);
    PUT replaces all of them."""

    goal_completions: bool
    streak_milestones: bool
    health_insights: bool
    hydration_reminders: bool
    nutrition_reminders: bool
    sleep_reminders: bool
    daily_checkin: bool
    health_profile_reminders: bool
    connection_requests: bool
    connection_activity: bool
    reports_ready: bool
    subscription_payments: bool


def _whole_minute(value: object) -> object:
    if (
        getattr(value, "second", 0)
        or getattr(value, "microsecond", 0)
        or getattr(value, "tzinfo", None)
    ):
        raise ValueError("times are HH:MM local times")
    return value


ReminderTime = Annotated[JsonTime, AfterValidator(_whole_minute)]


class ReminderIn(_Model):
    type: ReminderType
    enabled: bool
    times: Annotated[list[ReminderTime], Field(max_length=12, default_factory=list)]
    interval_min: Annotated[int, Field(ge=60, le=240)] | None = None

    @model_validator(mode="after")
    def _schedule(self) -> Self:
        if len(set(self.times)) != len(self.times):
            raise ValueError("times must be distinct")
        if self.times and self.interval_min is not None:
            raise ValueError("times or an interval, not both")
        if self.enabled and not self.times and self.interval_min is None:
            raise ValueError("an enabled reminder needs times or an interval")
        return self


class RemindersIn(_Model):
    reminders: Annotated[list[ReminderIn], Field(max_length=5)]

    @model_validator(mode="after")
    def _unique_types(self) -> Self:
        types = [r.type for r in self.reminders]
        if len(set(types)) != len(types):
            raise ValueError("one schedule per type")
        return self
