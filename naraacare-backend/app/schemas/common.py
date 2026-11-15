"""Shared field types for request schemas.

Models are ``strict=True`` (no silent coercion, e.g. ``"5"`` is not an int). FastAPI validates the
parsed JSON in Python mode, where strict UUID/Decimal/time accept only their own Python types, so
these fields opt out of strictness individually: a UUID string, a JSON number for a decimal and an
``HH:MM`` string are parsed, and their own format/range checks still apply.
"""

from __future__ import annotations

from datetime import time
from decimal import Decimal
from typing import Annotated
from uuid import UUID

from pydantic import Strict

JsonUUID = Annotated[UUID, Strict(False)]
JsonDecimal = Annotated[Decimal, Strict(False)]
JsonTime = Annotated[time, Strict(False)]
