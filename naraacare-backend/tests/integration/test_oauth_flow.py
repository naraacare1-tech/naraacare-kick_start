"""Google/Apple sign-in, never silently linking to an existing password account (OQ-30)."""

from __future__ import annotations

import time
import uuid
from typing import Any

import jwt
import pytest

from app.core.security.oauth import APPLE_ISSUER, JwksCache, OAuthVerifier, nonce_hash
from tests.conftest import AppFactory
from tests.integration.flows import (
    ADMIN_URL,
    INSTALLATION,
    PASSWORD,
    Flow,
    bearer,
    db_only,
    make_flow,
)
from tests.unit.core.test_oauth import PROVIDER_KEY, FakeFetch, jwks

pytestmark = db_only
NONCE = "nonce-for-test"


def provider_token(**claims: object) -> str:
    now = int(time.time())
    payload: dict[str, object] = {
        "iss": "https://accounts.google.com",
        "aud": "dummy-android.apps.googleusercontent.com",
        "sub": uuid.uuid4().hex,
        "email": f"g-{uuid.uuid4().hex[:10]}@example.com",
        "email_verified": True,
        "nonce": nonce_hash(NONCE),
        "iat": now,
        "exp": now + 600,
        **claims,
    }
    return jwt.encode(payload, PROVIDER_KEY, algorithm="RS256", headers={"kid": "g1"})


def oauth_flow(app_factory: AppFactory) -> Flow:
    fetch = FakeFetch(jwks(PROVIDER_KEY, "g1"))
    verifier = OAuthVerifier(
        google_keys=JwksCache("https://google.test/certs", fetch),
        apple_keys=JwksCache("https://apple.test/keys", fetch),
        google_client_ids=["dummy-android.apps.googleusercontent.com"],
        apple_audiences=["com.naraacare.app.dev"],
    )
    return make_flow(app_factory, oauth=verifier)


def google(flow: Flow, token: str) -> Any:
    return flow.client.post(
        "/api/v1/auth/oauth/google",
        json={"id_token": token, "nonce": NONCE, "installation_id": str(INSTALLATION)},
    )


def test_first_and_repeat_google_sign_in(app_factory: AppFactory) -> None:
    flow = oauth_flow(app_factory)
    subject = uuid.uuid4().hex
    email = f"g-{uuid.uuid4().hex[:10]}@example.com"
    first = google(flow, provider_token(sub=subject, email=email))
    assert first.status_code == 200, first.text
    assert first.json()["onboarding_required"] is True
    me = flow.client.get("/api/v1/me", headers=bearer(first.json())).json()
    assert me["email"] == email
    again = google(flow, provider_token(sub=subject, email=email))
    assert again.status_code == 200
    assert (
        flow.client.get("/api/v1/me", headers=bearer(again.json())).json()["user_id"]
        == me["user_id"]
    )


def test_unverified_email_and_bad_tokens_are_refused(app_factory: AppFactory) -> None:
    flow = oauth_flow(app_factory)
    assert google(flow, provider_token(email_verified=False)).status_code == 401
    assert google(flow, provider_token(aud="other-app")).status_code == 401
    assert google(flow, provider_token(nonce=nonce_hash("replayed"))).status_code == 401


def test_existing_password_account_requires_a_password_to_link(app_factory: AppFactory) -> None:
    flow = oauth_flow(app_factory)
    address, pair = flow.new_user()
    subject = uuid.uuid4().hex
    conflict = google(flow, provider_token(sub=subject, email=address))
    assert conflict.status_code == 409
    error = conflict.json()["error"]
    assert error["code"] == "LINK_REQUIRED" and address not in conflict.text
    link = {"link_token": error["link_token"], "installation_id": str(INSTALLATION)}
    wrong = flow.client.post("/api/v1/auth/oauth/link", json={**link, "password": "Wrong1Password"})
    assert wrong.status_code == 401
    forged = flow.client.post(
        "/api/v1/auth/oauth/link",
        json={**link, "link_token": pair["access_token"], "password": PASSWORD},
    )
    assert forged.status_code == 401  # an access token is not a link token
    linked = flow.client.post("/api/v1/auth/oauth/link", json={**link, "password": PASSWORD})
    assert linked.status_code == 200, linked.text
    direct = google(flow, provider_token(sub=subject, email=address))
    assert direct.status_code == 200  # linked now: no password needed any more
    same_user = flow.client.get("/api/v1/me", headers=bearer(direct.json())).json()["email"]
    assert same_user == address


def test_apple_sign_in_without_a_key_still_works(app_factory: AppFactory) -> None:
    flow = oauth_flow(app_factory)
    token = provider_token(iss=APPLE_ISSUER, aud="com.naraacare.app.dev", email_verified="true")
    response = flow.client.post(
        "/api/v1/auth/oauth/apple",
        json={
            "identity_token": token,
            "authorization_code": "c.code-from-apple",
            "nonce": NONCE,
            "installation_id": str(INSTALLATION),
        },
    )
    assert response.status_code == 200, response.text


@pytest.mark.skipif(ADMIN_URL is None, reason="NARAACARE_TEST_ADMIN_URL not set")
async def test_apple_refresh_token_is_stored(app_factory: AppFactory) -> None:
    import asyncpg  # noqa: PLC0415

    class FakeApple:
        async def exchange_code(self, code: str) -> str | None:
            return "r.apple-refresh-token" if code == "c.good" else None

    flow = oauth_flow(app_factory)
    flow.harness.app.state.auth_service.apple = FakeApple()
    subject = uuid.uuid4().hex
    token = provider_token(
        sub=subject, iss=APPLE_ISSUER, aud="com.naraacare.app.dev", email_verified="true"
    )
    response = flow.client.post(
        "/api/v1/auth/oauth/apple",
        json={
            "identity_token": token,
            "authorization_code": "c.good",
            "nonce": NONCE,
            "installation_id": str(INSTALLATION),
        },
    )
    assert response.status_code == 200
    user_id = flow.client.get("/api/v1/me", headers=bearer(response.json())).json()["user_id"]
    assert ADMIN_URL is not None
    conn = await asyncpg.connect(ADMIN_URL)
    try:
        stored = await conn.fetchval(
            "SELECT provider_refresh_token FROM auth.identity_link WHERE user_id = $1",
            uuid.UUID(user_id),
        )
    finally:
        await conn.close()
    assert stored == "r.apple-refresh-token"  # plain text (owner decision 2026-11-03)
