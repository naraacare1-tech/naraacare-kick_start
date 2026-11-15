"""Google and Apple sign-in (doc 07 SEC-1.4, OQ-30).

ID tokens are verified locally against the provider's published keys (JWKS), with PyJWT:
* signature RS256 with a key from the provider's JWKS (looked up by ``kid``; the key set is cached
  for an hour and refreshed early, at most once a minute, when an unknown ``kid`` appears);
* ``iss`` is the provider, ``aud`` is one of our client ids, ``exp``/``iat`` valid;
* ``nonce`` equals SHA-256(hex) of the raw nonce the app sends us (the app passes the hash to the
  provider), so a token captured from another app or replayed later is useless;
* ``email_verified`` must be true for an account to be created or matched by email.

Apple also requires deleting apps to revoke the user's tokens, so the ``authorization_code`` is
exchanged once at sign-in for a refresh token (``AppleTokenClient``), which is stored encrypted.
"""

from __future__ import annotations

import hashlib
import hmac
import time
from collections.abc import Awaitable, Callable, Sequence
from dataclasses import dataclass
from typing import Any

import httpx2
import jwt
import structlog
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePrivateKey

from app.core.security.tokens import TokenError

log = structlog.get_logger(__name__)

GOOGLE_ISSUERS = ("accounts.google.com", "https://accounts.google.com")
APPLE_ISSUER = (
    "https://appleid.apple.com"  # issuer identifier (a protocol constant, not an endpoint)
)
PROVIDER_ALGORITHMS = ["RS256"]
LEEWAY_S = 60
HTTP_TIMEOUT_S = 5.0

FetchJson = Callable[[str], Awaitable[dict[str, Any]]]


def http_fetcher(client: httpx2.AsyncClient) -> FetchJson:
    async def fetch(url: str) -> dict[str, Any]:
        response = await client.get(url, timeout=HTTP_TIMEOUT_S)
        response.raise_for_status()
        data: dict[str, Any] = response.json()
        return data

    return fetch


class JwksCache:
    def __init__(
        self,
        url: str,
        fetch: FetchJson,
        *,
        ttl_s: float = 3600,
        min_refresh_s: float = 60,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self._url = url
        self._fetch = fetch
        self._ttl_s = ttl_s
        self._min_refresh_s = min_refresh_s
        self._clock = clock
        self._keys: dict[str, jwt.PyJWK] = {}
        self._fetched_at: float | None = None

    async def _refresh(self) -> None:
        data = await self._fetch(self._url)
        keys: dict[str, jwt.PyJWK] = {}
        for item in data.get("keys", []):
            try:
                key = jwt.PyJWK(item)
            except jwt.PyJWTError:
                continue  # unsupported key types are skipped, not fatal
            if key.key_id:
                keys[key.key_id] = key
        self._keys = keys
        self._fetched_at = self._clock()

    async def key(self, kid: str) -> jwt.PyJWK:
        now = self._clock()
        stale = self._fetched_at is None or now - self._fetched_at > self._ttl_s
        unknown = kid not in self._keys
        may_refresh = self._fetched_at is None or now - self._fetched_at > self._min_refresh_s
        if stale or (unknown and may_refresh):
            try:
                await self._refresh()
            except (httpx2.HTTPError, ValueError) as exc:
                log.warning("jwks_refresh_failed", exc_type=type(exc).__name__)
        key = self._keys.get(kid)
        if key is None:
            raise TokenError
        return key


@dataclass(frozen=True, slots=True)
class ProviderIdentity:
    provider: str
    subject: str
    email: str | None
    email_verified: bool


def nonce_hash(raw_nonce: str) -> str:
    return hashlib.sha256(raw_nonce.encode("utf-8")).hexdigest()


def _is_true(value: object) -> bool:
    return value is True or value == "true"


class OAuthVerifier:
    def __init__(
        self,
        *,
        google_keys: JwksCache,
        apple_keys: JwksCache,
        google_client_ids: Sequence[str],
        apple_audiences: Sequence[str],
    ) -> None:
        self._google_keys = google_keys
        self._apple_keys = apple_keys
        self._google_client_ids = list(google_client_ids)
        self._apple_audiences = list(apple_audiences)

    async def _decode(
        self, token: str, keys: JwksCache, audiences: list[str], issuers: Sequence[str]
    ) -> dict[str, Any]:
        try:
            kid = jwt.get_unverified_header(token).get("kid")
            if not isinstance(kid, str):
                raise TokenError
            key = await keys.key(kid)
            claims: dict[str, Any] = jwt.decode(
                token,
                key,
                algorithms=PROVIDER_ALGORITHMS,
                audience=audiences,
                leeway=LEEWAY_S,
                options={"require": ["exp", "iat", "iss", "aud", "sub"], "verify_iss": False},
            )
        except jwt.PyJWTError:
            raise TokenError from None
        if claims.get("iss") not in issuers:
            raise TokenError
        return claims

    @staticmethod
    def _check_nonce(claims: dict[str, Any], raw_nonce: str) -> None:
        token_nonce = claims.get("nonce")
        if not isinstance(token_nonce, str) or not hmac.compare_digest(
            token_nonce, nonce_hash(raw_nonce)
        ):
            raise TokenError

    @staticmethod
    def _identity(provider: str, claims: dict[str, Any]) -> ProviderIdentity:
        email = claims.get("email")
        return ProviderIdentity(
            provider=provider,
            subject=str(claims["sub"]),
            email=email.strip().lower() if isinstance(email, str) and email.strip() else None,
            email_verified=_is_true(claims.get("email_verified")),
        )

    async def verify_google(self, id_token: str, raw_nonce: str) -> ProviderIdentity:
        claims = await self._decode(
            id_token, self._google_keys, self._google_client_ids, GOOGLE_ISSUERS
        )
        self._check_nonce(claims, raw_nonce)
        return self._identity("google", claims)

    async def verify_apple(self, identity_token: str, raw_nonce: str) -> ProviderIdentity:
        claims = await self._decode(
            identity_token, self._apple_keys, self._apple_audiences, (APPLE_ISSUER,)
        )
        self._check_nonce(claims, raw_nonce)
        return self._identity("apple", claims)


class AppleTokenClient:
    """Exchanges a Sign in with Apple authorization code for a refresh token (revocation later)."""

    def __init__(
        self,
        *,
        http: httpx2.AsyncClient,
        token_url: str,
        team_id: str,
        client_id: str,
        key_id: str,
        private_key: EllipticCurvePrivateKey,
        clock: Callable[[], float] = time.time,
    ) -> None:
        self._http = http
        self._token_url = token_url
        self._team_id = team_id
        self._client_id = client_id
        self._key_id = key_id
        self._private_key = private_key
        self._clock = clock

    def client_secret(self) -> str:
        now = int(self._clock())
        claims = {
            "iss": self._team_id,
            "iat": now,
            "exp": now + 300,
            "aud": APPLE_ISSUER,
            "sub": self._client_id,
        }
        return jwt.encode(
            claims, self._private_key, algorithm="ES256", headers={"kid": self._key_id}
        )

    async def exchange_code(self, authorization_code: str) -> str | None:
        """The refresh token, or None when Apple refuses or is unreachable (logged, not fatal)."""
        try:
            response = await self._http.post(
                self._token_url,
                data={
                    "grant_type": "authorization_code",
                    "code": authorization_code,
                    "client_id": self._client_id,
                    "client_secret": self.client_secret(),
                },
                timeout=HTTP_TIMEOUT_S,
            )
            response.raise_for_status()
            token = response.json().get("refresh_token")
        except (httpx2.HTTPError, ValueError) as exc:
            log.warning("apple_code_exchange_failed", exc_type=type(exc).__name__)
            return None
        return token if isinstance(token, str) and token else None

    async def revoke(self, refresh_token: str, revoke_url: str) -> bool:
        """Revokes the user's Sign in with Apple tokens (App Store rule for account deletion, S15).
        False when Apple refuses or is unreachable (logged by type only; the token is never
        logged)."""
        try:
            response = await self._http.post(
                revoke_url,
                data={
                    "client_id": self._client_id,
                    "client_secret": self.client_secret(),
                    "token": refresh_token,
                    "token_type_hint": "refresh_token",  # nosec B105 - RFC 7009 hint name
                },
                timeout=HTTP_TIMEOUT_S,
            )
            response.raise_for_status()
        except httpx2.HTTPError as exc:
            log.warning("apple_revoke_failed", exc_type=type(exc).__name__)
            return False
        return True


def load_apple_private_key(p8: str) -> EllipticCurvePrivateKey | None:
    """The Sign in with Apple key, or None when the configured value is not a usable EC key."""
    try:
        key = serialization.load_pem_private_key(p8.encode(), password=None)
    except (ValueError, TypeError):
        return None
    return key if isinstance(key, EllipticCurvePrivateKey) else None
