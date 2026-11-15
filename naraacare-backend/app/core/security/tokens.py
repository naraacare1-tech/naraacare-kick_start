"""Access, link and refresh tokens (doc 07 SEC-1.2).

* Access token: JWT signed with Ed25519 (``EdDSA``), 15 minutes, header ``kid`` for key rotation.
  Claims ``sub, role, tier_hint, sid (refresh-token family), iat, exp, iss, aud, jti`` plus
  ``use=access``. Verified statelessly; revocation inside the 15 minutes is handled by
  ``app.core.security.authz`` (in-memory deny-list per session / per user).
* Link token: the same key, audience ``<aud>:link``, ``use=link``, 10 minutes. Proves which Google/
  Apple identity asked to be linked (POST /auth/oauth/link). It carries the provider subject and the
  email the provider verified (both already in the provider's id token the app holds); signed, so
  they cannot be changed.
* Refresh token: 256 random bits, opaque. The database stores only its SHA-256 (no keyed hash is
  needed: the value has full entropy, so the hash cannot be brute-forced).

Algorithm confusion is impossible: verification accepts only ``EdDSA`` with a key looked up by
``kid`` from the configured public keys; ``alg: none`` and HMAC tokens are rejected by PyJWT.
"""

from __future__ import annotations

import json
import secrets
import time
import uuid
from collections.abc import Callable, Mapping
from dataclasses import dataclass
from hashlib import sha256
from typing import Any
from uuid import UUID

import jwt
import structlog
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

log = structlog.get_logger(__name__)

ALGORITHM = "EdDSA"
LEEWAY_S = 30
REFRESH_TOKEN_BYTES = 32
_REQUIRED = ["exp", "iat", "iss", "aud", "sub", "jti"]


class TokenError(Exception):
    """The token is missing, malformed, forged, expired or of the wrong kind."""

    def __init__(self, *, expired: bool = False) -> None:
        super().__init__("token rejected")
        self.expired = expired


class TokenConfigError(RuntimeError):
    """Key material is missing or malformed (message never contains key material)."""


@dataclass(frozen=True, slots=True)
class AccessClaims:
    user_id: UUID
    role: str
    session_id: UUID
    tier_hint: str
    issued_at_ms: int  # millisecond precision for revocation cut-offs (``iat`` has seconds)


@dataclass(frozen=True, slots=True)
class LinkClaims:
    provider: str
    subject: str
    email: str


class TokenService:
    def __init__(
        self,
        *,
        private_key: Ed25519PrivateKey,
        kid: str,
        public_keys: Mapping[str, Ed25519PublicKey],
        issuer: str,
        audience: str,
        access_ttl_s: int,
        link_ttl_s: int,
        clock: Callable[[], float] = time.time,
    ) -> None:
        if kid not in public_keys:
            raise TokenConfigError("JWT_ACTIVE_KID has no public key")
        active_public = public_keys[kid].public_bytes_raw()
        if private_key.public_key().public_bytes_raw() != active_public:
            raise TokenConfigError("JWT private key does not match the active public key")
        self._private_key = private_key
        self._kid = kid
        self._public_keys = dict(public_keys)
        self._issuer = issuer
        self._audience = audience
        self._access_ttl_s = access_ttl_s
        self._link_ttl_s = link_ttl_s
        self._clock = clock

    @property
    def access_ttl_s(self) -> int:
        return self._access_ttl_s

    def _sign(self, claims: dict[str, Any], audience: str, ttl_s: int) -> str:
        clock = self._clock()
        now = int(clock)
        payload = {
            **claims,
            "iss": self._issuer,
            "aud": audience,
            "iat": now,
            "iat_ms": int(clock * 1000),
            "exp": now + ttl_s,
            "jti": str(uuid.uuid4()),
        }
        return jwt.encode(
            payload, self._private_key, algorithm=ALGORITHM, headers={"kid": self._kid}
        )

    def _verify(self, token: str, audience: str, use: str) -> dict[str, Any]:
        try:
            kid = jwt.get_unverified_header(token).get("kid")
            key = self._public_keys.get(kid) if isinstance(kid, str) else None
            if key is None:
                raise TokenError
            claims: dict[str, Any] = jwt.decode(
                token,
                key,
                algorithms=[ALGORITHM],
                audience=audience,
                issuer=self._issuer,
                # Time claims are checked below against the service clock (one source of time).
                options={
                    "require": _REQUIRED,
                    "verify_exp": False,
                    "verify_iat": False,
                    "verify_nbf": False,
                },
            )
        except jwt.PyJWTError:
            raise TokenError from None
        now = self._clock()
        try:
            expires_at, issued_at = int(claims["exp"]), int(claims["iat"])
        except (TypeError, ValueError):
            raise TokenError from None
        if issued_at > now + LEEWAY_S or claims.get("use") != use:
            raise TokenError
        if expires_at + LEEWAY_S < now:
            raise TokenError(expired=True)
        return claims

    def issue_access(self, *, user_id: UUID, role: str, session_id: UUID, tier_hint: str) -> str:
        claims = {
            "sub": str(user_id),
            "role": role,
            "sid": str(session_id),
            "tier_hint": tier_hint,
            "use": "access",
        }
        return self._sign(claims, self._audience, self._access_ttl_s)

    def verify_access(self, token: str) -> AccessClaims:
        claims = self._verify(token, self._audience, "access")
        try:
            return AccessClaims(
                user_id=UUID(claims["sub"]),
                role=str(claims["role"]),
                session_id=UUID(claims["sid"]),
                tier_hint=str(claims.get("tier_hint", "standard")),
                issued_at_ms=int(claims.get("iat_ms", int(claims["iat"]) * 1000)),
            )
        except (KeyError, TypeError, ValueError):
            raise TokenError from None

    def issue_link(self, *, provider: str, subject: str, email: str) -> str:
        claims = {
            "sub": f"{provider}:link",
            "provider": provider,
            "sbj": subject,
            "eml": email,
            "use": "link",
        }
        return self._sign(claims, f"{self._audience}:link", self._link_ttl_s)

    def verify_link(self, token: str) -> LinkClaims:
        claims = self._verify(token, f"{self._audience}:link", "link")
        try:
            return LinkClaims(
                provider=str(claims["provider"]),
                subject=str(claims["sbj"]),
                email=str(claims["eml"]),
            )
        except (KeyError, TypeError, ValueError):
            raise TokenError from None


def new_refresh_token() -> tuple[str, bytes]:
    """A fresh refresh token and the SHA-256 the database stores."""
    token = secrets.token_urlsafe(REFRESH_TOKEN_BYTES)
    return token, refresh_token_hash(token)


def refresh_token_hash(token: str) -> bytes:
    return sha256(token.encode("ascii")).digest()


def _load_private(pem: str) -> Ed25519PrivateKey:
    try:
        key = serialization.load_pem_private_key(pem.encode(), password=None)
    except (ValueError, TypeError):
        raise TokenConfigError("JWT_PRIVATE_KEY_PEM is not a PEM private key") from None
    if not isinstance(key, Ed25519PrivateKey):
        raise TokenConfigError("JWT_PRIVATE_KEY_PEM must be an Ed25519 key")
    return key


def _load_public_keys(keys_json: str) -> dict[str, Ed25519PublicKey]:
    try:
        raw: dict[str, str] = json.loads(keys_json)
        keys = {kid: serialization.load_pem_public_key(pem.encode()) for kid, pem in raw.items()}
    except (ValueError, TypeError, AttributeError):
        raise TokenConfigError("JWT_PUBLIC_KEYS_JSON must map key ids to PEM public keys") from None
    if not all(isinstance(k, Ed25519PublicKey) for k in keys.values()):
        raise TokenConfigError("JWT_PUBLIC_KEYS_JSON must hold Ed25519 keys")
    return {kid: k for kid, k in keys.items() if isinstance(k, Ed25519PublicKey)}


def build_token_service(
    *,
    private_key_pem: str | None,
    public_keys_json: str | None,
    kid: str,
    issuer: str,
    audience: str,
    access_ttl_s: int,
    link_ttl_s: int,
) -> TokenService:
    """Configured keys, or (dev only; the settings refuse it elsewhere) an ephemeral key pair."""
    if private_key_pem is None or public_keys_json is None:
        log.warning("jwt_ephemeral_key", reason="JWT keys not configured (dev)")
        private_key = Ed25519PrivateKey.generate()
        public_keys = {kid: private_key.public_key()}
    else:
        private_key = _load_private(private_key_pem)
        public_keys = _load_public_keys(public_keys_json)
    return TokenService(
        private_key=private_key,
        kid=kid,
        public_keys=public_keys,
        issuer=issuer,
        audience=audience,
        access_ttl_s=access_ttl_s,
        link_ttl_s=link_ttl_s,
    )
