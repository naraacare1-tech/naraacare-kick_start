"""Rate limits (Session 16, doc 07 SEC-3.2 / T1, T19, T27).

* Structure: every state-changing route carries a per-route policy (``rate_limit`` by IP or
  ``user_limit`` by user), except the listed ones; every policy in POLICIES is used.
* Behaviour: the global per-user limit (300/min) and a per-user route policy answer 429 with
  ``Retry-After``, count per user (one user's burst never limits another) and reset with the window.
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator, Sequence
from pathlib import Path
from typing import Any

import pytest
from fastapi.routing import APIRoute

from app.core.memory_store import MemoryStore
from app.core.security.tokens import TokenService
from app.middleware.rate_limit import POLICIES, RateLimiter
from tests.conftest import AppFactory, AppHarness

APP = Path(__file__).resolve().parents[2] / "app"

# State-changing routes without a per-route policy, and why that is safe.
UNLIMITED = {
    "POST /api/v1/auth/logout": "only ends the caller's own session (global limits apply)",
    "POST /api/v1/auth/logout-all": "only ends the caller's own sessions (global limits apply)",
    "POST /api/v1/billing/webhooks/google": "provider push; signature checked first; global IP",
    "POST /api/v1/billing/webhooks/apple": "provider push; signature checked first; global IP",
}
# Policies used outside route dependencies: middleware, current_user, and the per-email ones the
# auth service applies once it has read the body.
USED_IN_CODE = {
    "global_ip",
    "global_user",
    "penalty",
    "auth_signup_email",
    "auth_login_account",
    "auth_password_forgot_email",
}


def _policy_names(call: Any) -> list[str]:
    if call is None or not getattr(call, "__closure__", None):
        return []
    cells = zip(call.__code__.co_freevars, call.__closure__, strict=True)
    return [cell.cell_contents for name, cell in cells if name == "policy_name"]


def _from_dependant(dependant: Any) -> list[str]:
    names = _policy_names(dependant.call)
    for child in dependant.dependencies:
        names += _from_dependant(child)
    return names


def route_policies(
    routes: Sequence[Any], prefix: str = "", inherited: Sequence[Any] = ()
) -> Iterator[tuple[str, list[str]]]:
    """("METHOD /path", policy names) for every API route, through included routers."""
    for route in routes:
        if isinstance(route, APIRoute):
            names = _from_dependant(route.dependant)
            for dep in inherited:
                names += _policy_names(dep.dependency)
            for method in sorted(route.methods or ()):
                yield f"{method} {prefix}{route.path}", names
        elif hasattr(route, "original_router"):
            context = route.include_context
            yield from route_policies(
                route.original_router.routes,
                prefix + context.prefix,
                (*inherited, *context.dependencies),
            )


@pytest.fixture
def harness(app_factory: AppFactory) -> AppHarness:
    return app_factory()


def test_every_state_changing_route_has_a_policy(harness: AppHarness) -> None:
    missing = [
        route
        for route, names in route_policies(harness.app.routes)
        if not route.startswith("GET ") and not names and route not in UNLIMITED
    ]
    assert missing == []


def test_exemptions_are_current(harness: AppHarness) -> None:
    served = dict(route_policies(harness.app.routes))
    stale = [route for route in UNLIMITED if route not in served or served[route]]
    assert stale == []


def test_every_policy_is_used(harness: AppHarness) -> None:
    used = {name for _, names in route_policies(harness.app.routes) for name in names}
    assert sorted(POLICIES.keys() - used - USED_IN_CODE) == []
    for name in USED_IN_CODE:
        assert any(f'"{name}"' in f.read_text(encoding="utf-8") for f in APP.rglob("*.py")), name


# --------------------------------------------------------------------------- behaviour
class Clock:
    def __init__(self) -> None:
        self.now = 1_800_000_000.0

    def __call__(self) -> float:
        return self.now


def limited_app(app_factory: AppFactory) -> tuple[AppHarness, Clock]:
    clock = Clock()
    harness = app_factory()
    harness.app.state.rate_limiter = RateLimiter(MemoryStore(), clock=clock)
    return harness, clock


def token_for(harness: AppHarness, user_id: uuid.UUID) -> dict[str, str]:
    tokens: TokenService = harness.app.state.tokens
    access = tokens.issue_access(
        user_id=user_id, role="user", session_id=uuid.uuid4(), tier_hint="standard"
    )
    return {"Authorization": f"Bearer {access}"}


def test_global_per_user_limit(app_factory: AppFactory) -> None:
    harness, clock = limited_app(app_factory)
    alice, bob = token_for(harness, uuid.uuid4()), token_for(harness, uuid.uuid4())
    limit = POLICIES["global_user"].limit
    # The global IP limit (600/min) is higher, so the per-user one is what stops Alice.
    statuses = [harness.client.get("/api/v1/me", headers=alice).status_code for _ in range(limit)]
    assert 429 not in statuses
    blocked = harness.client.get("/api/v1/me", headers=alice)
    assert blocked.status_code == 429
    assert blocked.json()["error"]["code"] == "RATE_LIMITED"
    assert int(blocked.headers["Retry-After"]) >= 1
    assert harness.client.get("/api/v1/me", headers=bob).status_code != 429  # per user
    clock.now += POLICIES["global_user"].window_s + 1
    assert harness.client.get("/api/v1/me", headers=alice).status_code != 429  # window reset


def test_route_policy_counts_per_user(app_factory: AppFactory) -> None:
    harness, _ = limited_app(app_factory)
    alice, bob = token_for(harness, uuid.uuid4()), token_for(harness, uuid.uuid4())
    limit = POLICIES["username_availability"].limit
    path, params = "/api/v1/usernames/availability", {"username": "priya.s"}
    for _ in range(limit):
        assert harness.client.get(path, params=params, headers=alice).status_code != 429
    assert harness.client.get(path, params=params, headers=alice).status_code == 429
    assert harness.client.get(path, params=params, headers=bob).status_code != 429


def test_global_ip_limit_applies_before_authentication(app_factory: AppFactory) -> None:
    harness, _ = limited_app(app_factory)
    limit = POLICIES["global_ip"].limit
    for _ in range(limit):
        harness.client.get("/api/v1/health/live")
    response = harness.client.get("/api/v1/me")  # no token: refused by IP before 401
    assert response.status_code == 429
