"""Signed-up, onboarded test users and admin SQL for the ``-m db`` tests."""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from typing import Any

from tests.integration.flows import ADMIN_URL, Flow, bearer
from tests.integration.test_profile_flow import CONSENTS, onboard


async def sql(statement: str, *args: object) -> list[Any]:
    """Runs one statement as the database superuser (test set-up and inspection only)."""
    import asyncpg  # noqa: PLC0415

    assert ADMIN_URL is not None
    conn = await asyncpg.connect(ADMIN_URL)
    try:
        return list(await conn.fetch(statement, *args))
    finally:
        await conn.close()


class User:
    def __init__(self, flow: Flow, consents: Sequence[dict[str, Any]] = CONSENTS) -> None:
        self.flow = flow
        self.email, pair = flow.new_user()
        self.headers = bearer(pair)
        onboard(flow, self.headers)  # DOC example 1: target 2214 kcal
        done = flow.client.post(
            "/api/v1/me/onboarding/complete",
            headers=self.headers,
            json={"consents": list(consents)},
        )
        assert done.status_code == 201, done.text
        self.id = uuid.UUID(flow.client.get("/api/v1/me", headers=self.headers).json()["user_id"])

    async def make_star(self) -> None:
        await sql(
            "INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)"
            " VALUES ($1, 'star', 'promo', now() - interval '1 day', now() + interval '30 days')",
            self.id,
        )
