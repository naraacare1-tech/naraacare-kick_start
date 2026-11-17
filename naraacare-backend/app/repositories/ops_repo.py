"""Owner-alert health check (worker role only): counts from ``ops.fn_ops_health``, no user data."""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any

from app.repositories.base import DbSession, db_call

HEALTH = db_call("SELECT * FROM ops.fn_ops_health()")


async def health(session: DbSession) -> Mapping[str, Any]:
    return await session.fetch_one(HEALTH) or {}
