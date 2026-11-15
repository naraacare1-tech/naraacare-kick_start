"""Sleep requests (doc 04 section 2.6). No free text at all: times are timestamps and the goal is an
integer. Models forbid unknown fields and carry no ``user_id``. The database validates again
(16 h limit, wakings inside the interval, no overlap)."""

from __future__ import annotations

from datetime import timedelta
from typing import Annotated, Self

from pydantic import Field, model_validator

from app.schemas.common import JsonUUID
from app.schemas.nutrition import JsonDateTime, _Model

MAX_ENTRY = timedelta(hours=16)


class NightWaking(_Model):
    woke_at: JsonDateTime
    back_asleep_at: JsonDateTime

    @model_validator(mode="after")
    def _order(self) -> Self:
        if self.back_asleep_at <= self.woke_at:
            raise ValueError("back_asleep_at must be after woke_at")
        return self


class _Entry(_Model):
    sleep_start: JsonDateTime
    wake_time: JsonDateTime
    wakings: Annotated[list[NightWaking], Field(max_length=10, default_factory=list)]

    @model_validator(mode="after")
    def _interval(self) -> Self:
        if self.wake_time <= self.sleep_start:
            raise ValueError("wake_time must be after sleep_start")
        if self.wake_time - self.sleep_start > MAX_ENTRY:
            raise ValueError("an entry can be at most 16 hours")
        previous = self.sleep_start
        for w in self.wakings:
            if w.woke_at < previous or w.back_asleep_at > self.wake_time:
                raise ValueError("night wakings must be inside the sleep and in order")
            previous = w.back_asleep_at
        return self


class SleepEntryCreate(_Entry):
    client_entry_id: JsonUUID


class SleepEntryUpdate(_Entry):
    pass


class SleepGoalIn(_Model):
    goal_min: Annotated[int, Field(ge=240, le=720)]
