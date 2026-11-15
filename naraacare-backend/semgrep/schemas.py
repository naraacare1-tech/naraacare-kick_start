# Semgrep test fixture for schemas.yml (run: semgrep --test semgrep/). Not application code.
from typing import Annotated, Optional

from pydantic import BaseModel, Field

from app.core.security.validators import SafeName, SafeSearchQuery


class BadRequest(BaseModel):
    # ruleid: no-bare-str-in-schemas
    name: str
    # ruleid: no-bare-str-in-schemas
    note: str = ""
    # ruleid: no-bare-str-in-schemas
    nickname: str | None = None
    # ruleid: no-bare-str-in-schemas
    city: Optional[str] = None
    # ruleid: no-bare-str-in-schemas
    tags: list[str] = []
    # ruleid: no-bare-str-in-schemas
    bio: Annotated[str, Field(max_length=10)]


class GoodRequest(BaseModel):
    # ok: no-bare-str-in-schemas
    name: SafeName
    # ok: no-bare-str-in-schemas
    query: SafeSearchQuery | None = None
    # ok: no-bare-str-in-schemas
    count: int = 0
