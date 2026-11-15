"""Google/Apple ID token verification with a local JWKS (doc 07 SEC-1.4)."""

from __future__ import annotations

import json
import time
from typing import Any

import httpx2
import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

from app.core.security.oauth import (
    APPLE_ISSUER,
    AppleTokenClient,
    JwksCache,
    OAuthVerifier,
    load_apple_private_key,
    nonce_hash,
)
from app.core.security.tokens import TokenError

PROVIDER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
ROGUE_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
NONCE = "raw-nonce-123"
NOW = int(time.time())


def jwks(key: rsa.RSAPrivateKey, kid: str) -> dict[str, Any]:
    public = json.loads(jwt.algorithms.RSAAlgorithm.to_jwk(key.public_key()))
    return {"keys": [{**public, "kid": kid, "alg": "RS256", "use": "sig"}]}


class FakeFetch:
    def __init__(self, document: dict[str, Any]) -> None:
        self.document = document
        self.calls = 0

    async def __call__(self, url: str) -> dict[str, Any]:
        self.calls += 1
        return self.document


def token(
    key: rsa.RSAPrivateKey = PROVIDER_KEY,
    kid: str = "g1",
    extra: dict[str, object] | None = None,
    **claims: object,
) -> str:
    claims = {**(extra or {}), **claims}
    payload: dict[str, object] = {
        "iss": "https://accounts.google.com",
        "aud": "android-client",
        "sub": "1234567890",
        "email": "Priya@Example.com",
        "email_verified": True,
        "nonce": nonce_hash(NONCE),
        "iat": int(time.time()),  # at call time: slow suites can run long before this test
        "exp": int(time.time()) + 600,
        **claims,
    }
    return jwt.encode(payload, key, algorithm="RS256", headers={"kid": kid})


def verifier(fetch: FakeFetch | None = None) -> OAuthVerifier:
    fetch = fetch or FakeFetch(jwks(PROVIDER_KEY, "g1"))
    return OAuthVerifier(
        google_keys=JwksCache("https://google.test/certs", fetch),
        apple_keys=JwksCache("https://apple.test/keys", fetch),
        google_client_ids=["android-client", "ios-client"],
        apple_audiences=["com.naraacare.app", "com.naraacare.app.siwa"],
    )


async def test_valid_google_token() -> None:
    identity = await verifier().verify_google(token(), NONCE)
    assert identity.provider == "google"
    assert identity.subject == "1234567890"
    assert identity.email == "priya@example.com"
    assert identity.email_verified


@pytest.mark.parametrize(
    "bad",
    [
        {"aud": "someone-elses-app"},
        {"iss": "https://evil.example"},
        {"nonce": nonce_hash("other")},
        {"nonce": NONCE},  # raw nonce instead of its hash
        {"exp": NOW - 3600, "iat": NOW - 7200},
    ],
)
async def test_bad_google_claims_are_rejected(bad: dict[str, object]) -> None:
    with pytest.raises(TokenError):
        await verifier().verify_google(token(extra=bad), NONCE)


async def test_token_signed_by_another_key_is_rejected() -> None:
    with pytest.raises(TokenError):
        await verifier().verify_google(token(key=ROGUE_KEY), NONCE)


async def test_unverified_email_is_reported() -> None:
    identity = await verifier().verify_google(token(email_verified=False), NONCE)
    assert not identity.email_verified


async def test_apple_token_without_email_on_later_sign_ins() -> None:
    apple = token(iss=APPLE_ISSUER, aud="com.naraacare.app", email=None, email_verified="true")
    identity = await verifier().verify_apple(apple, NONCE)
    assert identity.provider == "apple" and identity.email is None


async def test_google_token_is_not_accepted_as_apple() -> None:
    with pytest.raises(TokenError):
        await verifier().verify_apple(token(), NONCE)


async def test_unknown_kid_refreshes_once_then_fails() -> None:
    fetch = FakeFetch(jwks(PROVIDER_KEY, "g1"))
    keys = JwksCache("https://google.test/certs", fetch, clock=lambda: 1000.0)
    await keys.key("g1")
    assert fetch.calls == 1
    with pytest.raises(TokenError):
        await keys.key("rotated")
    assert fetch.calls == 1  # no refetch storm within the minimum refresh interval


async def test_rotated_key_is_picked_up_after_the_interval() -> None:
    now = [1000.0]
    fetch = FakeFetch(jwks(PROVIDER_KEY, "g1"))
    keys = JwksCache("https://google.test/certs", fetch, clock=lambda: now[0])
    await keys.key("g1")
    fetch.document = jwks(ROGUE_KEY, "g2")
    now[0] += 61
    assert (await keys.key("g2")).key_id == "g2"


async def test_jwks_outage_keeps_cached_keys() -> None:
    now = [1000.0]

    class Flaky(FakeFetch):
        async def __call__(self, url: str) -> dict[str, Any]:
            self.calls += 1
            if self.calls > 1:
                raise httpx2.ConnectError("down")
            return self.document

    keys = JwksCache(
        "https://google.test/certs", Flaky(jwks(PROVIDER_KEY, "g1")), clock=lambda: now[0]
    )
    await keys.key("g1")
    now[0] += 4000  # stale: refresh fails, cached key still served
    assert (await keys.key("g1")).key_id == "g1"


def _apple_key() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


async def test_apple_code_exchange() -> None:
    seen: dict[str, Any] = {}
    key = _apple_key()

    def handler(request: httpx2.Request) -> httpx2.Response:
        seen["body"] = request.content.decode()
        return httpx2.Response(200, json={"refresh_token": "r.apple.token", "id_token": "x"})

    async with httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http:
        client = AppleTokenClient(
            http=http,
            token_url="https://apple.test/token",
            team_id="TEAM123456",
            client_id="com.naraacare.app",
            key_id="KEY1234567",
            private_key=key,
        )
        assert await client.exchange_code("c.code") == "r.apple.token"
        secret = jwt.decode(
            client.client_secret(), key.public_key(), algorithms=["ES256"], audience=APPLE_ISSUER
        )
    assert secret["iss"] == "TEAM123456" and secret["sub"] == "com.naraacare.app"
    assert "grant_type=authorization_code" in seen["body"]


async def test_apple_code_exchange_failure_is_not_fatal() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        return httpx2.Response(400, json={"error": "invalid_grant"})

    async with httpx2.AsyncClient(transport=httpx2.MockTransport(handler)) as http:
        client = AppleTokenClient(
            http=http,
            token_url="https://apple.test/token",
            team_id="T",
            client_id="c",
            key_id="k",
            private_key=_apple_key(),
        )
        assert await client.exchange_code("c.code") is None


def test_apple_key_loading() -> None:
    pem = (
        _apple_key()
        .private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.PKCS8,
            serialization.NoEncryption(),
        )
        .decode()
    )
    assert load_apple_private_key(pem) is not None
    assert load_apple_private_key("dummy-not-a-key") is None
