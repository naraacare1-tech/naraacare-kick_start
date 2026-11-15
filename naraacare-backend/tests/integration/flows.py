"""Helpers for the Session 05 flow tests against a real database (``-m db``)."""

from __future__ import annotations

import os
import uuid
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.security.hashing import Hasher
from app.middleware.rate_limit import Decision
from app.repositories.base import Database
from tests.conftest import AppFactory, AppHarness

DB_URL = os.environ.get("NARAACARE_TEST_DATABASE_URL")
ADMIN_URL = os.environ.get("NARAACARE_TEST_ADMIN_URL")
db_only = [
    pytest.mark.db,
    pytest.mark.skipif(DB_URL is None, reason="NARAACARE_TEST_DATABASE_URL not set"),
]
PASSWORD = "Correct1Horse"
POLICIES = {"terms": "0.0-draft", "privacy": "0.0-draft"}


@dataclass
class SentEmail:
    to: str
    template: str
    values: Mapping[str, str]


@dataclass
class RecordingEmail:
    sent: list[SentEmail] = field(default_factory=list)

    async def send(self, to: str, template: str, values: Mapping[str, str]) -> None:
        self.sent.append(SentEmail(to, template, dict(values)))

    def last_code(self, to: str) -> str:
        return next(
            m.values["code"] for m in reversed(self.sent) if m.to == to and "code" in m.values
        )


class NoLimits:
    async def hit(self, *_: object) -> Decision:
        return Decision(allowed=True)

    async def enforce(self, *_: object) -> None:
        return None

    async def in_penalty_box(self, _: str) -> bool:
        return False

    async def record_unsafe_rejection(self, _: str) -> bool:
        return False


@dataclass
class Flow:
    harness: AppHarness
    email: RecordingEmail

    @property
    def client(self) -> Any:
        return self.harness.client

    def signup(self, address: str, password: str = PASSWORD) -> dict[str, Any]:
        response = self.client.post(
            "/api/v1/auth/signup",
            json={
                "email": address,
                "password": password,
                "confirm_password": password,
                "accept_terms": True,
                "policy_versions": POLICIES,
                "installation_id": str(INSTALLATION),
            },
        )
        assert response.status_code == 201, response.text
        body: dict[str, Any] = response.json()
        return body

    def verify(self, challenge_id: str, code: str) -> Any:
        return self.client.post(
            "/api/v1/auth/otp/verify",
            json={"challenge_id": challenge_id, "code": code, "installation_id": str(INSTALLATION)},
        )

    def new_user(self, password: str = PASSWORD) -> tuple[str, dict[str, Any]]:
        """A verified account; returns (email, token pair)."""
        address = f"user-{uuid.uuid4().hex[:12]}@example.com"
        challenge = self.signup(address, password)
        response = self.verify(challenge["challenge_id"], self.email.last_code(address))
        assert response.status_code == 200, response.text
        pair: dict[str, Any] = response.json()
        return address, pair

    def login(
        self, address: str, password: str = PASSWORD, installation: uuid.UUID | None = None
    ) -> Any:
        return self.client.post(
            "/api/v1/auth/login",
            json={
                "email": address,
                "password": password,
                "installation_id": str(installation or INSTALLATION),
            },
        )


INSTALLATION = uuid.uuid4()


def real_db() -> Database:
    assert DB_URL is not None
    return Database(create_async_engine(DB_URL, connect_args={"statement_cache_size": 0}))


def make_flow(app_factory: AppFactory, *, limits: bool = False, **state: object) -> Flow:
    email = RecordingEmail()
    preset: dict[str, object] = {
        "email": email,
        # Cheap Argon2 parameters keep the suite fast; the production profile is tested in S04.
        "password_hasher": Hasher(memory_kib=8192, time_cost=1, parallelism=1),
        "otp_hasher": Hasher(memory_kib=8192, time_cost=1, parallelism=1),
        **state,
    }
    if not limits:
        preset["rate_limiter"] = NoLimits()
    harness = app_factory(db=real_db(), state=preset)
    return Flow(harness=harness, email=email)


def bearer(pair: Mapping[str, Any]) -> dict[str, str]:
    return {"Authorization": f"Bearer {pair['access_token']}"}
