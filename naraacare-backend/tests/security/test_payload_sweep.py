"""Run the payload sweep over the whole API plus an echo router covering every input location."""

from __future__ import annotations

import uuid
from typing import Annotated, Any

import pytest
from fastapi import APIRouter, Header, Path, Query
from pydantic import BaseModel, ConfigDict, Field

from app.api.v1.routers import admin_foods
from app.core.security.authz import Principal
from app.core.security.validators import (
    SafeChatMessage,
    SafeName,
    SafeOpaqueToken128,
    SafeSearchQuery,
    SafeShortText60,
    SafeText500,
    SafeUsername,
)
from app.middleware.rate_limit import Decision
from tests.conftest import AppFactory
from tests.security.payload_sweep import (
    Operation,
    discover,
    sweep,
    unvalidated_string_fields,
)
from tests.security.payloads import load_payloads

PAYLOADS = load_payloads()


class Item(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    label: SafeShortText60
    quantity: Annotated[int, Field(ge=1, le=10)]


class EchoBody(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    name: SafeName
    username: SafeUsername
    note: SafeText500 | None = None
    message: SafeChatMessage
    items: Annotated[list[Item], Field(min_length=1, max_length=5)]


echo_router = APIRouter()


@echo_router.post("/sweep/{circle_code}")
async def sweep_echo(
    circle_code: Annotated[SafeOpaqueToken128, Path()],
    body: EchoBody,
    q: Annotated[SafeSearchQuery, Query()] = "dal",
    x_client_tag: Annotated[SafeOpaqueToken128 | None, Header()] = None,
) -> dict[str, Any]:
    return {"ok": True}


class NoLimits:
    """Thousands of hostile requests come from one address here; limits are tested elsewhere."""

    async def hit(self, *_: object) -> Decision:
        return Decision(allowed=True)

    async def enforce(self, *_: object) -> None:
        return None

    async def in_penalty_box(self, _: str) -> bool:
        return False

    async def record_unsafe_rejection(self, _: str) -> bool:
        return False


def test_every_string_field_in_the_api_is_a_safe_type(app_factory: AppFactory) -> None:
    harness = app_factory()
    assert unvalidated_string_fields(harness.app.openapi()) == []


def test_bare_string_fields_are_detected(app_factory: AppFactory) -> None:
    router = APIRouter()

    @router.get("/bare")
    async def bare(q: str) -> dict[str, str]:  # deliberately unvalidated
        return {"q": q}

    harness = app_factory(routers=[router])
    assert unvalidated_string_fields(harness.app.openapi()) == ["GET /api/v1/bare query:q"]


def test_discovery_finds_every_input_location(app_factory: AppFactory) -> None:
    harness = app_factory(routers=[echo_router])
    ops = [op for op in discover(harness.app.openapi()) if op.path.endswith("{circle_code}")]
    assert len(ops) == 1
    names = {(t.location, t.name) for t in ops[0].targets}
    assert names == {
        ("path", "circle_code"),
        ("query", "q"),
        ("header", "x-client-tag"),
        ("body", "name"),
        ("body", "username"),
        ("body", "note"),
        ("body", "message"),
        ("body", "items.0.label"),
    }


@pytest.mark.slow
def test_every_payload_is_rejected_on_every_field(
    app_factory: AppFactory, capsys: pytest.CaptureFixture[str]
) -> None:
    harness = app_factory(routers=[echo_router])
    harness.app.state.rate_limiter = NoLimits()
    operations = discover(harness.app.openapi())
    user_id = uuid.uuid4()
    # Staff routes answer 404 before validation for anyone outside the role and the IP allow-list
    # (tested in the nutrition tests); here they are opened so their bodies reach validation.
    harness.app.dependency_overrides[admin_foods.staff_only] = lambda: Principal(
        user_id=user_id, role="nutritionist", session_id=uuid.uuid4(), tier_hint="standard"
    )

    def headers_for(op: Operation) -> dict[str, str]:
        # A fresh access token per request: the sweep grows with every endpoint and, on a slow
        # machine with coverage on, can outlast one token's 15-minute lifetime (a 401 would then
        # be reported as a field that was not rejected).
        if not op.secured:
            return {}
        token = harness.app.state.tokens.issue_access(
            user_id=user_id, role="user", session_id=uuid.uuid4(), tier_hint="standard"
        )
        return {"Authorization": f"Bearer {token}"}

    # The echo route's baseline (valid) request must succeed, or the sweep would prove nothing for
    # it. Real routes need the database to succeed; for them the sweep proves that every hostile
    # value is rejected by validation before any handler runs (S05 integration tests cover the
    # valid paths against a real database).
    echo = [op for op in operations if op.path.endswith("{circle_code}")]
    for op in echo:
        url = op.path.format(**op.path_params)
        response = harness.client.request(
            op.method.upper(), url, params=op.query, headers=op.headers, json=op.body
        )
        assert response.status_code == 200, (op.path, response.text)

    result = sweep(harness.client, operations, PAYLOADS, headers_for=headers_for)
    fields = sum(len(op.targets) for op in operations)
    print(f"payload sweep: {result.requests} requests over {fields} string fields")  # noqa: T201
    # Header payloads the HTTP client cannot even send (control chars, non-ASCII) are skipped.
    assert fields >= 30
    assert result.requests >= len(PAYLOADS) * (fields - 1)
    assert result.failures == [], "\n".join(result.failures[:20])

    logs = capsys.readouterr().out
    leaked = [p for p in PAYLOADS if len(p) >= 8 and p in logs]
    assert leaked == [], f"{len(leaked)} payloads appear in logs"
    # Markup/script rejections are reported as security events (never with the value). Payloads
    # that only fail an allow-list (e.g. SQL strings with no markup in an OTP, email or code field)
    # are format errors and, by design, not events. With the strict-format auth fields of
    # Session 05 that is ~25 % of all requests (it was ~15 % with the free-text echo fields only).
    assert len(harness.events.events) >= result.requests * 0.7
    assert all(e.event_type == "validation_rejected" for e in harness.events.events)
