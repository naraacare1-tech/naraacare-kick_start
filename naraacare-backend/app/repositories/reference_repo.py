"""Reference data (doc 04 section 2.3) and the calculation context (doc 06)."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any

from app.repositories.base import DbSession, db_call

BOOTSTRAP = db_call("SELECT * FROM ref.fn_bootstrap()")
CALC_CONTEXT = db_call("SELECT ref.fn_calc_context() AS context")
POLICIES = db_call("SELECT * FROM ref.fn_policies()")


async def bootstrap(session: DbSession) -> Mapping[str, Any]:
    row = await session.fetch_one(BOOTSTRAP)
    return row or {}


async def calc_context(session: DbSession) -> Any:
    return await session.fetch_value(CALC_CONTEXT)


async def policies(session: DbSession) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(POLICIES)
