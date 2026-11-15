"""Per-route auth rate limits (doc 04 section 2.1 Rate column) and token-based access control.
No database needed: limits are enforced before any handler work."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends

from app.core.security.authz import CurrentUser, Principal, require_role
from tests.conftest import AppFactory

SIGNUP = {
    "password": "Correct1Horse",
    "confirm_password": "Correct1Horse",
    "accept_terms": True,
    "policy_versions": {"terms": "0.0-draft", "privacy": "0.0-draft"},
}


def test_signup_is_limited_per_ip_and_per_email(app_factory: AppFactory) -> None:
    harness = app_factory()
    client = harness.client

    def signup(email: str) -> int:
        body = {**SIGNUP, "email": email, "installation_id": str(uuid.uuid4())}
        return client.post("/api/v1/auth/signup", json=body).status_code

    same_email = [signup("priya@example.com") for _ in range(4)]
    assert same_email[-1] == 429  # 3 per hour per email
    assert all(code != 429 for code in same_email[:3])
    others = [signup(f"p{i}@example.com") for i in range(2)]
    assert others[-1] == 429  # 5 per hour per IP in total


def test_login_is_limited_per_ip(app_factory: AppFactory) -> None:
    harness = app_factory()
    body = {"password": "Correct1Horse", "installation_id": str(uuid.uuid4())}
    codes = [
        harness.client.post(
            "/api/v1/auth/login", json={**body, "email": f"u{i}@example.com"}
        ).status_code
        for i in range(11)
    ]
    assert codes[-1] == 429 and 429 not in codes[:10]
    assert harness.client.post(
        "/api/v1/auth/login", json={**body, "email": "x@example.com"}
    ).headers["Retry-After"]


def _protected_routes() -> APIRouter:
    router = APIRouter()

    @router.get("/whoami")
    async def whoami(principal: CurrentUser) -> dict[str, str]:
        return {"user_id": str(principal.user_id), "role": principal.role}

    @router.get("/staff")
    async def staff(
        principal: Annotated[Principal, Depends(require_role("admin", "support"))],
    ) -> dict[str, str]:
        return {"ok": "yes"}

    return router


def test_access_control_with_tokens(app_factory: AppFactory) -> None:
    harness = app_factory(routers=[_protected_routes()])
    tokens = harness.app.state.tokens
    user = uuid.uuid4()
    token = tokens.issue_access(
        user_id=user, role="user", session_id=uuid.uuid4(), tier_hint="standard"
    )
    client = harness.client

    def get(path: str, value: str | None) -> tuple[int, str]:
        headers = {"Authorization": value} if value else {}
        response = client.get(f"/api/v1{path}", headers=headers)
        return response.status_code, response.json().get("error", {}).get("code", "")

    assert get("/whoami", None) == (401, "UNAUTHENTICATED")
    assert get("/whoami", "Basic dXNlcjpwYXNz") == (401, "UNAUTHENTICATED")
    assert get("/whoami", "Bearer not.a.token") == (401, "UNAUTHENTICATED")
    ok = client.get("/api/v1/whoami", headers={"Authorization": f"Bearer {token}"})
    assert ok.json() == {"user_id": str(user), "role": "user"}
    assert get("/staff", f"Bearer {token}") == (404, "NOT_FOUND")  # role mismatch looks like 404
    admin = tokens.issue_access(
        user_id=user, role="admin", session_id=uuid.uuid4(), tier_hint="standard"
    )
    assert get("/staff", f"Bearer {admin}")[0] == 200


async def test_revocations_fail_open_when_redis_is_down() -> None:
    from app.core.security.authz import Revocations  # noqa: PLC0415
    from app.core.security.tokens import AccessClaims  # noqa: PLC0415

    class DownRedis:
        async def set(self, *_: object, **__: object) -> None:
            raise ConnectionError("down")

        async def exists(self, *_: object) -> int:
            raise ConnectionError("down")

        async def get(self, *_: object) -> None:
            raise ConnectionError("down")

    revocations = Revocations(DownRedis(), ttl_s=900)
    claims = AccessClaims(uuid.uuid4(), "user", uuid.uuid4(), "standard", 0)
    await revocations.revoke_session(claims.session_id)  # logged, not raised
    await revocations.revoke_user(claims.user_id)
    assert await revocations.is_revoked(claims) is False
