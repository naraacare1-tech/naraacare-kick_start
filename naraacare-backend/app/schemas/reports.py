"""Reports, Help & Support and sync requests (doc 04 sections 2.11, 2.13, 2.14). No user id from
the client; every text field is a Safe* type (no markup or scripts, checked again by the
database)."""

from __future__ import annotations

from datetime import date
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, Strict, model_validator

from app.core.security.validators import (
    SafeShortText120,
    SafeText1000,
    SafeText2000,
    SafeYearMonth,
)
from app.schemas.nutrition import _Model

JsonDate = Annotated[date, Strict(False)]
Section = Literal["hydration", "nutrition", "sleep", "insights"]
MAX_RANGE_DAYS = 365  # from..to inclusive = 366 days


class ReportRequest(_Model):
    type: Literal["monthly", "custom"]
    month: SafeYearMonth | None = None
    from_: Annotated[JsonDate | None, Field(alias="from")] = None
    to: JsonDate | None = None
    sections: Annotated[list[Section], Field(min_length=1, max_length=4)]

    @model_validator(mode="after")
    def _shape(self) -> ReportRequest:
        if self.type == "monthly" and (self.month is None or self.from_ or self.to):
            raise ValueError("a monthly report needs month only")
        if self.type == "custom":
            if self.month is not None or self.from_ is None or self.to is None:
                raise ValueError("a custom report needs from and to")
            if self.from_ > self.to or (self.to - self.from_).days > MAX_RANGE_DAYS:
                raise ValueError("from must be before to, at most 366 days")
        if len(set(self.sections)) != len(self.sections) or self.sections == ["insights"]:
            raise ValueError("sections must be distinct and include a tracker")
        return self


class FeatureRequestIn(_Model):
    title: SafeShortText120
    benefit: SafeText1000


TicketCategory = Literal["app_crash", "data_sync", "billing", "device_link", "account", "other"]


class TicketForm(BaseModel):
    """The text parts of the multipart ``POST /support/tickets``. FastAPI hands every form part to
    this model, so the file part ``screenshot`` is the one extra key allowed; any other is
    rejected."""

    model_config = ConfigDict(extra="allow", strict=True)

    category: TicketCategory
    description: SafeText2000

    @model_validator(mode="after")
    def _only_known_parts(self) -> TicketForm:
        if set(self.model_extra or {}) - {"screenshot"}:
            raise ValueError("unknown form field")
        return self
