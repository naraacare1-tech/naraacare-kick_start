"""Effective tier and feature switches (doc 04 section 3).

``billing.fn_current_entitlement`` decides (store subscription or grant, else STANDARD). It is read
from the database on every call, with no cache (owner decision, 2026-11-03), so a purchase or a
grant applies on the very next request.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID

from app.repositories.base import Database, DbSession, db_call

CURRENT_ENTITLEMENT = db_call("SELECT * FROM billing.fn_current_entitlement(:user_id)")


@dataclass(frozen=True, slots=True)
class Entitlement:
    tier: str
    source: str
    expires_at: str | None  # RFC 3339
    features: dict[str, bool]
    limits: dict[str, int]

    def allows(self, feature: str) -> bool:
        return self.features.get(feature, False)


def _from_row(row: dict[str, Any]) -> Entitlement:
    def as_obj(value: object) -> dict[str, Any]:
        loaded = json.loads(value) if isinstance(value, str | bytes) else value
        return dict(loaded) if isinstance(loaded, dict) else {}

    expires: datetime | None = row.get("expires_at")
    return Entitlement(
        tier=str(row["tier_code"]),
        source=str(row["source"]),
        expires_at=expires.isoformat() if expires else None,
        features={k: bool(v) for k, v in as_obj(row["features"]).items()},
        limits={k: int(v) for k, v in as_obj(row["limits"]).items()},
    )


async def load(session: DbSession, user_id: UUID) -> Entitlement:
    row = await session.fetch_one(CURRENT_ENTITLEMENT, user_id=user_id)
    if row is None:  # the function always returns a row; defensive
        return Entitlement("standard", "default", None, {}, {})
    return _from_row(dict(row))


class EntitlementService:
    def __init__(self, db: Database) -> None:
        self._db = db

    async def get(self, user_id: UUID) -> Entitlement:
        return await self._db.run(lambda s: load(s, user_id), user_id=user_id, readonly=True)
