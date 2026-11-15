"""Entitlements: read from the database on every call (no cache)."""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from typing import Any

from app.domain.entitlements.service import Entitlement, EntitlementService, _from_row

STAR = Entitlement(
    tier="star",
    source="store",
    expires_at="2026-12-01T00:00:00+00:00",
    features={"sleep": True},
    limits={"meal_logs_per_day": 8},
)


class CountingDb:
    def __init__(self) -> None:
        self.calls = 0

    async def run(self, work: Callable[[Any], Awaitable[Entitlement]], **_: object) -> Entitlement:
        self.calls += 1
        return STAR


async def test_every_read_goes_to_the_database() -> None:
    db = CountingDb()
    service = EntitlementService(db)  # type: ignore[arg-type]
    user = uuid.uuid4()
    assert await service.get(user) == STAR
    assert await service.get(user) == STAR
    assert db.calls == 2


def test_row_parsing_accepts_json_text_from_the_driver() -> None:
    entitlement = _from_row(
        {
            "tier_code": "standard",
            "source": "default",
            "expires_at": None,
            "features": '{"sleep": false, "rin_ai": false}',
            "limits": '{"meal_logs_per_day": 4}',
        }
    )
    assert entitlement.tier == "standard" and not entitlement.allows("sleep")
    assert entitlement.limits == {"meal_logs_per_day": 4}
