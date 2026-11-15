"""JWT attacks over HTTP (Session 16, doc 07 SEC-1.2 / T1-T3).

The unit suite (tests/unit/core/test_tokens.py) proves the verifier; these tests prove the running
app: forged and foreign tokens get 401 (never 500) on a protected route, hostile ``kid`` / ``jku`` /
``jwk`` headers are ignored, tokens are only read from the Authorization header, a tampered
``tier_hint`` unlocks nothing, revoked sessions stay revoked, and the signing key can be rotated
with an overlap (the rotation drill, runbooks/key_rotation.md).
"""

from __future__ import annotations

import base64
import json
import time
import uuid
from collections.abc import Callable, Iterator

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.core.security.tokens import TokenService
from tests.conftest import AppFactory, AppHarness
from tests.integration.flows import ADMIN_URL, DB_URL, PASSWORD, Flow, bearer, make_flow
from tests.integration.users import User

PROTECTED = "/api/v1/me/entitlements"


def b64(data: dict[str, object]) -> str:
    return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()


def pem(key: Ed25519PrivateKey) -> str:
    return key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()


def public_pem(key: Ed25519PrivateKey) -> str:
    return (
        key.public_key()
        .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        .decode()
    )


def with_header(token: str, **changes: object) -> str:
    header, payload, signature = token.split(".")
    fields = json.loads(base64.urlsafe_b64decode(header + "=="))
    fields.update(changes)
    return f"{b64(fields)}.{payload}.{signature}"


def with_claims(token: str, **changes: object) -> str:
    header, payload, signature = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
    claims.update(changes)
    return f"{header}.{b64(claims)}.{signature}"


@pytest.fixture
def harness(app_factory: AppFactory) -> AppHarness:
    return app_factory()


def issue(harness: AppHarness, **overrides: object) -> str:
    tokens: TokenService = harness.app.state.tokens
    params: dict[str, object] = {
        "user_id": uuid.uuid4(),
        "role": "user",
        "session_id": uuid.uuid4(),
        "tier_hint": "standard",
        **overrides,
    }
    return tokens.issue_access(**params)  # type: ignore[arg-type]


ATTACKER = Ed25519PrivateKey.generate()

FORGERIES: dict[str, Callable[[str], str]] = {
    "alg none": lambda t: f"{b64({'alg': 'none', 'typ': 'JWT'})}.{t.split('.')[1]}.",
    "alg None (case)": lambda t: f"{b64({'alg': 'None', 'typ': 'JWT'})}.{t.split('.')[1]}.",
    "alg HS256 header": lambda t: with_header(t, alg="HS256"),
    "role escalated": lambda t: with_claims(t, role="admin"),
    "sub swapped": lambda t: with_claims(t, sub=str(uuid.uuid4())),
    "exp pushed": lambda t: with_claims(t, exp=4_102_444_800),
    "kid traversal": lambda t: with_header(t, kid="../../../../dev/null"),
    "kid sql": lambda t: with_header(t, kid="k1' OR '1'='1"),
    "kid object": lambda t: with_header(t, kid={"$ne": None}),
    "kid empty": lambda t: with_header(t, kid=""),
    "jku injected": lambda t: with_header(t, jku="https://evil.example/jwks.json", kid="evil"),
    "x5u injected": lambda t: with_header(t, x5u="https://evil.example/cert.pem", kid="evil"),
    "jwk embedded": lambda t: with_header(
        t, kid="evil", jwk={"kty": "OKP", "crv": "Ed25519", "x": "AAAA"}
    ),
    "signature stripped": lambda t: t.rsplit(".", 1)[0] + ".",
    "two segments": lambda t: t.rsplit(".", 1)[0],
    "extra segment": lambda t: t + ".AAAA",
    "huge token": lambda t: t + "A" * 20_000,
    "non-ascii": lambda t: t[:-2] + "é",
}


@pytest.mark.parametrize("name", FORGERIES)
def test_forged_tokens_get_401_on_a_protected_route(harness: AppHarness, name: str) -> None:
    token = FORGERIES[name](issue(harness))
    try:
        response = harness.client.get(PROTECTED, headers={"Authorization": f"Bearer {token}"})
    except UnicodeEncodeError:
        return  # the HTTP client cannot even send it; nothing reached the server
    assert response.status_code in {401, 431}, response.text
    if response.status_code == 401:
        assert response.json()["error"]["code"] == "UNAUTHENTICATED"


def test_token_signed_by_an_attacker_key_with_our_kid_is_refused(harness: AppHarness) -> None:
    forged = TokenService(
        private_key=ATTACKER,
        kid="k1",
        public_keys={"k1": ATTACKER.public_key()},
        issuer=harness.app.state.settings.JWT_ISSUER,
        audience=harness.app.state.settings.JWT_AUDIENCE,
        access_ttl_s=900,
        link_ttl_s=600,
    ).issue_access(user_id=uuid.uuid4(), role="admin", session_id=uuid.uuid4(), tier_hint="star")
    response = harness.client.get(PROTECTED, headers={"Authorization": f"Bearer {forged}"})
    assert response.status_code == 401


def test_link_token_is_not_an_access_token(harness: AppHarness) -> None:
    tokens: TokenService = harness.app.state.tokens
    link = tokens.issue_link(provider="google", subject="123", email="a@example.com")
    response = harness.client.get(PROTECTED, headers={"Authorization": f"Bearer {link}"})
    assert response.status_code == 401


def test_expired_token_says_token_expired(harness: AppHarness) -> None:
    tokens: TokenService = harness.app.state.tokens
    tokens._clock = lambda: 1_000_000_000.0  # issued in 2001
    old = issue(harness)
    tokens._clock = time.time
    response = harness.client.get(PROTECTED, headers={"Authorization": f"Bearer {old}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "TOKEN_EXPIRED"


@pytest.mark.parametrize(
    "where",
    ["query access_token", "query token", "cookie", "lowercase scheme", "no scheme"],
)
def test_tokens_are_read_only_from_the_authorization_header(
    harness: AppHarness, where: str
) -> None:
    token = issue(harness)
    client = harness.client
    if where == "query access_token":
        response = client.get(PROTECTED, params={"access_token": token})
    elif where == "query token":
        response = client.get(PROTECTED, params={"token": token})
    elif where == "cookie":
        client.cookies.set("access_token", token)
        response = client.get(PROTECTED)
        client.cookies.clear()
    elif where == "lowercase scheme":
        # RFC 7235: the scheme is case-insensitive, so this one IS accepted (control case).
        response = client.get(PROTECTED, headers={"Authorization": f"bearer {token}"})
        assert response.status_code != 401
        return
    else:
        response = client.get(PROTECTED, headers={"Authorization": token})
    assert response.status_code == 401


# --------------------------------------------------------------------------- key rotation drill
def test_signing_key_rotation_with_overlap(app_factory: AppFactory) -> None:
    """Step 1: k1 signs. Step 2: k2 signs, k1 still verifies (overlap = one access-token lifetime).
    Step 3: k1 removed -> its tokens are refused. No restart of clients needed."""
    k1, k2 = Ed25519PrivateKey.generate(), Ed25519PrivateKey.generate()

    def app_with(active: Ed25519PrivateKey, kid: str, published: dict[str, str]) -> AppHarness:
        return app_factory(
            JWT_PRIVATE_KEY_PEM=pem(active),
            JWT_PUBLIC_KEYS_JSON=json.dumps(published),
            JWT_ACTIVE_KID=kid,
        )

    def status(harness: AppHarness, token: str) -> int:
        headers = {"Authorization": f"Bearer {token}"}
        return int(harness.client.get(PROTECTED, headers=headers).status_code)

    step1 = app_with(k1, "k1", {"k1": public_pem(k1)})
    old = issue(step1)
    assert status(step1, old) != 401

    step2 = app_with(k2, "k2", {"k1": public_pem(k1), "k2": public_pem(k2)})
    new = issue(step2)
    assert status(step2, old) != 401
    assert status(step2, new) != 401

    step3 = app_with(k2, "k2", {"k2": public_pem(k2)})
    assert status(step3, old) == 401
    assert status(step3, new) != 401


# --------------------------------------------------------------------------- with a database
@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory)


@pytest.mark.db
@pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")
def test_tampered_tier_hint_unlocks_nothing(flow: Flow) -> None:
    """The tier comes from the database, never from the token: a STANDARD user's token re-signed
    with ``tier_hint: star`` (as if the key leaked) still gets 403 on a STAR route."""
    user = User(flow)
    tokens: TokenService = flow.harness.app.state.tokens
    me = flow.client.get("/api/v1/me", headers=user.headers).json()
    star_token = tokens.issue_access(
        user_id=uuid.UUID(me["user_id"]), role="user", session_id=uuid.uuid4(), tier_hint="star"
    )
    response = flow.client.get(
        "/api/v1/sleep/summary", headers={"Authorization": f"Bearer {star_token}"}
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "UPGRADE_REQUIRED"


@pytest.mark.db
@pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")
def test_replay_after_logout_all_and_password_change_is_refused(flow: Flow) -> None:
    address, first = flow.new_user()
    second = flow.login(address).json()
    for pair in (first, second):
        assert flow.client.get(PROTECTED, headers=bearer(pair)).status_code == 200

    assert flow.client.post("/api/v1/auth/logout-all", headers=bearer(first)).status_code == 204
    for pair in (first, second):
        assert flow.client.get(PROTECTED, headers=bearer(pair)).status_code == 401
        refreshed = flow.client.post(
            "/api/v1/auth/token/refresh",
            json={"refresh_token": pair["refresh_token"], "installation_id": str(uuid.uuid4())},
        )
        assert refreshed.status_code == 401

    third = flow.login(address).json()
    other_device = flow.login(address, installation=uuid.uuid4()).json()
    changed = flow.client.post(
        "/api/v1/auth/password/change",
        headers=bearer(third),
        json={
            "current_password": PASSWORD,
            "new_password": "Another2Horse",
            "confirm_password": "Another2Horse",
        },
    )
    assert changed.status_code in {200, 204}, changed.text
    # The device that changed the password stays signed in; every other session ends at once.
    assert flow.client.get(PROTECTED, headers=bearer(third)).status_code == 200
    assert flow.client.get(PROTECTED, headers=bearer(other_device)).status_code == 401
    # ...and a later logout-all still ends the kept session.
    assert flow.client.post("/api/v1/auth/logout-all", headers=bearer(third)).status_code == 204
    assert flow.client.get(PROTECTED, headers=bearer(third)).status_code == 401
