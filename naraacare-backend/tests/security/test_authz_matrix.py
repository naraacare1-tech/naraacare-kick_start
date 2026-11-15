"""Authorization matrix (Session 16, doc 07 SEC-1.5): every route x caller -> expected status.

``authz_matrix.yaml`` says who may call each route. The tests here prove it:

* the matrix lists exactly the routes the app serves (a new route fails until it is classified);
* no token, a garbage token or a token for another audience -> 401 on every non-public route;
* a signed-in user or a staff member outside the IP allow-list -> 404 on staff routes;
* a STANDARD user -> 403 UPGRADE_REQUIRED on every STAR route, a STAR user gets past the gate
  (real database, ``-m db``).

Requests are the payload sweep's valid baselines, so the gate is the only reason to refuse them.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import pytest
import yaml

from app.core.security.tokens import TokenService
from tests.conftest import AppFactory, AppHarness
from tests.fakes import FakeRinModel
from tests.integration.flows import ADMIN_URL, DB_URL, Flow, make_flow
from tests.integration.users import User
from tests.security.payload_sweep import Operation, discover

MATRIX: dict[str, dict[str, str]] = yaml.safe_load(
    (Path(__file__).parent / "authz_matrix.yaml").read_text(encoding="utf-8")
)["routes"]


def key(op: Operation) -> str:
    return f"{op.method.upper()} {op.path}"


def send(harness: AppHarness, op: Operation, headers: dict[str, str]) -> Any:
    return harness.client.request(
        op.method.upper(),
        op.path.format(**op.path_params),
        params=op.query,
        headers={**op.headers, **headers},
        json=op.body,
    )


def token(harness: AppHarness, role: str = "user", user_id: uuid.UUID | None = None) -> str:
    tokens: TokenService = harness.app.state.tokens
    return tokens.issue_access(
        user_id=user_id or uuid.uuid4(), role=role, session_id=uuid.uuid4(), tier_hint="standard"
    )


@pytest.fixture
def harness(app_factory: AppFactory) -> AppHarness:
    built = app_factory()
    built.app.state.rate_limiter = _NoLimits()
    return built


class _NoLimits:
    async def hit(self, *_: object) -> Any:
        from app.middleware.rate_limit import Decision  # noqa: PLC0415

        return Decision(allowed=True)

    async def enforce(self, *_: object) -> None:
        return None

    async def in_penalty_box(self, _: str) -> bool:
        return False

    async def record_unsafe_rejection(self, _: str) -> bool:
        return False


def operations(harness: AppHarness) -> list[Operation]:
    return discover(harness.app.openapi())


# --------------------------------------------------------------------------- the matrix itself
def test_matrix_lists_exactly_the_served_routes(harness: AppHarness) -> None:
    served = {key(op) for op in operations(harness)}
    assert sorted(served - MATRIX.keys()) == [], "classify these routes in authz_matrix.yaml"
    assert sorted(MATRIX.keys() - served) == [], "these matrix rows match no route"


def test_matrix_rows_are_well_formed() -> None:
    for route, row in MATRIX.items():
        access = row["access"]
        assert access in {"public", "user"} or access.startswith("staff:"), route
        assert set(row) <= {"access", "star", "note"}, route
        if "star" in row:
            assert access == "user", route


def test_openapi_security_agrees_with_the_matrix(harness: AppHarness) -> None:
    """A route documented without a token must be public in the matrix, and the other way round."""
    for op in operations(harness):
        public = MATRIX[key(op)]["access"] == "public"
        assert op.secured is not public, key(op)


# --------------------------------------------------------------------------- authentication
BAD_TOKENS = {
    "none": None,
    "garbage": "Bearer not-a-jwt",
    "empty": "Bearer ",
    "basic scheme": "Basic dXNlcjpwYXNz",
}


@pytest.mark.parametrize("case", BAD_TOKENS)
def test_every_private_route_refuses_a_missing_or_bad_token(harness: AppHarness, case: str) -> None:
    value = BAD_TOKENS[case]
    headers = {} if value is None else {"Authorization": value}
    wrong = []
    for op in operations(harness):
        if MATRIX[key(op)]["access"] == "public":
            continue
        response = send(harness, op, headers)
        if response.status_code != 401:
            wrong.append(f"{key(op)} -> {response.status_code}")
    assert wrong == []


def test_public_routes_ignore_the_authorization_header(harness: AppHarness) -> None:
    """Public routes answer the same with no token and with a garbage one: the header is never
    consulted (they may still answer 401 for a bad credential in the body, e.g. a forged Google
    ID token)."""
    for op in operations(harness):
        if MATRIX[key(op)]["access"] != "public":
            continue
        plain = send(harness, op, {}).status_code
        assert send(harness, op, {"Authorization": "Bearer junk"}).status_code == plain, key(op)


# --------------------------------------------------------------------------- staff routes
@pytest.mark.parametrize("role", ["user", "support", "nutritionist"])
def test_staff_routes_answer_404_to_everyone_outside_the_role_and_network(
    harness: AppHarness, role: str
) -> None:
    """``testclient`` is not an IP address inside STAFF_IP_ALLOWLIST, so even the right role
    gets 404 here (inside the allow-list it is covered by the nutrition admin tests)."""
    headers = {"Authorization": f"Bearer {token(harness, role)}"}
    for op in operations(harness):
        if not MATRIX[key(op)]["access"].startswith("staff:"):
            continue
        response = send(harness, op, headers)
        assert response.status_code == 404, (key(op), response.text)
        assert response.json()["error"]["code"] == "NOT_FOUND"


# --------------------------------------------------------------------------- STAR routes (DB)
@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory, rin_model=FakeRinModel())


def with_valid_sleep(op: Operation) -> Operation:
    """The sweep's generated sleep entry has a waking outside the night; use a real one."""
    if op.path.startswith("/api/v1/sleep/entries") and op.method in {"post", "put"}:
        wake = datetime.now(UTC).replace(microsecond=0) - timedelta(hours=1)
        op.body = {
            **op.body,
            "sleep_start": (wake - timedelta(hours=7)).isoformat(),
            "wake_time": wake.isoformat(),
            "wakings": [],
        }
    return op


@pytest.mark.db
@pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")
async def test_star_routes_refuse_standard_and_admit_star(flow: Flow) -> None:
    consents = [
        {"purpose": "health_data", "policy_version": "0.0-draft", "granted": True},
        {"purpose": "ai_processing", "policy_version": "0.0-draft", "granted": True},
    ]
    standard = User(flow, consents)
    star = User(flow, consents)
    await star.make_star()
    star_ops = [
        with_valid_sleep(op) for op in operations(flow.harness) if "star" in MATRIX[key(op)]
    ]
    assert len(star_ops) >= 10
    wrong = []
    for op in star_ops:
        refused = send(flow.harness, op, standard.headers)
        body = refused.json() if refused.headers.get("content-type", "").startswith("app") else {}
        code = body.get("error", {}).get("code")
        if refused.status_code != 403 or code != "UPGRADE_REQUIRED":
            wrong.append(f"STANDARD {key(op)} -> {refused.status_code} {code}")
        admitted = send(flow.harness, op, star.headers)
        if admitted.status_code == 403 and "UPGRADE_REQUIRED" in admitted.text:
            wrong.append(f"STAR {key(op)} -> still UPGRADE_REQUIRED")
    assert wrong == [], "\n".join(wrong)
