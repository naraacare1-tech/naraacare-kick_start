"""Access, link and refresh tokens (doc 07 SEC-1.2): the JWT tampering suite."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import uuid
from collections.abc import Callable

import jwt
import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.core.security.tokens import (
    TokenConfigError,
    TokenError,
    TokenService,
    build_token_service,
    new_refresh_token,
    refresh_token_hash,
)

KEY = Ed25519PrivateKey.generate()
OTHER = Ed25519PrivateKey.generate()
USER = uuid.uuid4()
SID = uuid.uuid4()


def service(clock: Callable[[], float] = lambda: 1_800_000_000.0, **kwargs: object) -> TokenService:
    params: dict[str, object] = {
        "private_key": KEY,
        "kid": "k1",
        "public_keys": {"k1": KEY.public_key()},
        "issuer": "https://api.test",
        "audience": "naraacare-mobile",
        "access_ttl_s": 900,
        "link_ttl_s": 600,
        "clock": clock,
        **kwargs,
    }
    return TokenService(**params)  # type: ignore[arg-type]


def access() -> str:
    return service().issue_access(user_id=USER, role="user", session_id=SID, tier_hint="star")


def test_round_trip_claims() -> None:
    claims = service().verify_access(access())
    assert (claims.user_id, claims.role, claims.session_id, claims.tier_hint) == (
        USER,
        "user",
        SID,
        "star",
    )
    header = jwt.get_unverified_header(access())
    assert header["alg"] == "EdDSA" and header["kid"] == "k1"


def test_expired_token_is_reported_as_expired() -> None:
    token = access()
    with pytest.raises(TokenError) as info:
        service(clock=lambda: 1_800_000_000.0 + 900 + 31).verify_access(token)
    assert info.value.expired


def _b64(data: dict[str, object]) -> str:
    return base64.urlsafe_b64encode(json.dumps(data).encode()).rstrip(b"=").decode()


def _hmac_with_public_key() -> str:
    """HS256 token signed with the PEM of the public key (PyJWT refuses to build one itself)."""
    public_pem = KEY.public_key().public_bytes(
        serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    claims = json.loads(base64.urlsafe_b64decode(access().split(".")[1] + "=="))
    signing_input = f"{_b64({'alg': 'HS256', 'typ': 'JWT', 'kid': 'k1'})}.{_b64(claims)}"
    signature = hmac.new(public_pem, signing_input.encode(), hashlib.sha256).digest()
    return f"{signing_input}.{base64.urlsafe_b64encode(signature).rstrip(b'=').decode()}"


def _tamper(token: str, **changes: object) -> str:
    header, payload, signature = token.split(".")
    claims = json.loads(base64.urlsafe_b64decode(payload + "=="))
    claims.update(changes)
    return f"{header}.{_b64(claims)}.{signature}"


@pytest.mark.parametrize(
    "make",
    [
        lambda: _tamper(access(), role="admin"),  # privilege escalation
        lambda: _tamper(access(), sub=str(uuid.uuid4())),  # impersonation
        lambda: f"{_b64({'alg': 'none', 'typ': 'JWT'})}.{access().split('.')[1]}.",  # alg none
        _hmac_with_public_key,  # algorithm confusion: HMAC keyed with the public key
        lambda: service(private_key=OTHER, public_keys={"k1": OTHER.public_key()}).issue_access(
            user_id=USER, role="user", session_id=SID, tier_hint="standard"
        ),  # signed by a different key
        lambda: service(kid="k9", public_keys={"k9": KEY.public_key()}).issue_access(
            user_id=USER, role="user", session_id=SID, tier_hint="standard"
        ),  # unknown kid
        lambda: service(audience="other-app").issue_access(
            user_id=USER, role="user", session_id=SID, tier_hint="standard"
        ),  # wrong audience
        lambda: service(issuer="https://evil").issue_access(
            user_id=USER, role="user", session_id=SID, tier_hint="standard"
        ),  # wrong issuer
        lambda: "not-a-jwt",
        lambda: access()[:-4] + "AAAA",  # broken signature
    ],
)
def test_forged_or_foreign_tokens_are_rejected(make: Callable[[], str]) -> None:
    token = make()
    with pytest.raises(TokenError) as info:
        service().verify_access(token)
    assert not info.value.expired


def test_link_and_access_tokens_are_not_interchangeable() -> None:
    svc = service()
    link = svc.issue_link(provider="google", subject="1234567890", email="asha@example.test")
    claims = svc.verify_link(link)
    assert (claims.provider, claims.subject, claims.email) == (
        "google",
        "1234567890",
        "asha@example.test",
    )
    with pytest.raises(TokenError):
        svc.verify_access(link)
    with pytest.raises(TokenError):
        svc.verify_link(access())


def test_token_issued_in_the_future_is_rejected() -> None:
    token = service(clock=lambda: 1_800_000_000.0 + 3600).issue_access(
        user_id=USER, role="user", session_id=SID, tier_hint="standard"
    )
    with pytest.raises(TokenError):
        service().verify_access(token)


def test_refresh_tokens_are_random_and_only_their_hash_is_stored() -> None:
    first, first_hash = new_refresh_token()
    second, _ = new_refresh_token()
    assert first != second and len(first) >= 43
    assert first_hash == refresh_token_hash(first) and len(first_hash) == 32


def _pem(key: Ed25519PrivateKey) -> str:
    return key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
    ).decode()


def _pub(key: Ed25519PrivateKey) -> str:
    return (
        key.public_key()
        .public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
        .decode()
    )


def test_build_from_configured_keys_and_ephemeral_dev_key() -> None:
    common = {
        "kid": "k1",
        "issuer": "i",
        "audience": "a",
        "access_ttl_s": 900,
        "link_ttl_s": 600,
    }
    built = build_token_service(
        private_key_pem=_pem(KEY),
        public_keys_json=json.dumps({"k1": _pub(KEY)}),
        **common,  # type: ignore[arg-type]
    )
    token = built.issue_access(user_id=USER, role="user", session_id=SID, tier_hint="standard")
    assert built.verify_access(token).user_id == USER
    ephemeral = build_token_service(private_key_pem=None, public_keys_json=None, **common)  # type: ignore[arg-type]
    with pytest.raises(TokenError):
        ephemeral.verify_access(token)


@pytest.mark.parametrize(
    ("private_pem", "public_json", "message"),
    [
        ("not a key", json.dumps({"k1": _pub(KEY)}), "not a PEM private key"),
        (_pem(KEY), "{not json", "must map key ids"),
        (_pem(KEY), json.dumps({"k1": _pub(OTHER)}), "does not match"),
        (_pem(KEY), json.dumps({"k2": _pub(KEY)}), "has no public key"),
    ],
)
def test_bad_key_configuration_fails_without_key_material(
    private_pem: str, public_json: str, message: str
) -> None:
    with pytest.raises(TokenConfigError, match=message) as info:
        build_token_service(
            private_key_pem=private_pem,
            public_keys_json=public_json,
            kid="k1",
            issuer="i",
            audience="a",
            access_ttl_s=900,
            link_ttl_s=600,
        )
    assert "PRIVATE KEY-----" not in str(info.value)
