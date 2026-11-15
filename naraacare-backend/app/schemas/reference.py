"""Reference endpoints (doc 04 section 2.3). The bootstrap payload is served as stored (database
reference rows, no user data), so it has no response model here."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, HttpUrl

from app.core.security.validators import SafeShortText20


class PolicyOut(BaseModel):
    type: Literal["terms", "privacy", "licenses"]
    version: SafeShortText20
    url: HttpUrl
    published_at: datetime | None


class PoliciesResponse(BaseModel):
    policies: list[PolicyOut]
