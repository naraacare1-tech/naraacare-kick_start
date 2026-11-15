"""Authentication and authorisation dependencies (doc 07 SEC-1.5).

* ``current_user``: Bearer access token -> ``Principal``. The user id comes ONLY from the token
  (``sub``); no endpoint accepts a user id from the client. Sets the request's user for logging,
  rate limits and the database actor.
* Revocation within the access token's 15 minutes: logout puts the session (``sid``) on a deny-list
  in the API's memory store, logout-all / password reset store a per-user cut-off time (tokens
  issued before it are refused, compared in milliseconds). Entries live as long as an access token
  can. The list is per API process and lost on restart: the refresh tokens are already revoked in
  the database, so a stolen access token stays usable for at most its remaining minutes.
* Every authenticated request counts against the global per-user limit (300/min).
* ``require_role`` / ``require_staff`` (role + IP allow-list) for staff routes; ``user_limit``
  applies a per-user rate-limit policy after authentication (route-level ``dependencies``
  would run before the user is known).
"""

from __future__ import annotations

import ipaddress
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from typing import Annotated, Any, Protocol
from uuid import UUID

import structlog
from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.request_context import set_user_id
from app.core.security.tokens import AccessClaims, TokenError, TokenService
from app.middleware.rate_limit import POLICIES, RateLimiter, client_ip

log = structlog.get_logger(__name__)

bearer_scheme = HTTPBearer(auto_error=False, description="Access token from /auth endpoints")


@dataclass(frozen=True, slots=True)
class Principal:
    user_id: UUID
    role: str
    session_id: UUID
    tier_hint: str


class SessionsEnded(Protocol):
    """Told when sessions are revoked (the WebSocket hub closes their sockets)."""

    async def __call__(
        self,
        *,
        user_id: UUID | None = None,
        session_id: UUID | None = None,
        keep_session: UUID | None = None,
    ) -> None: ...


class Revocations:
    def __init__(self, store: Any, ttl_s: int, clock: Callable[[], float] = time.time) -> None:
        self._store = store
        self._ttl_s = ttl_s
        self._clock = clock
        self.listeners: list[SessionsEnded] = []

    async def _notify(
        self,
        *,
        user_id: UUID | None = None,
        session_id: UUID | None = None,
        keep_session: UUID | None = None,
    ) -> None:
        for listener in self.listeners:
            try:
                await listener(user_id=user_id, session_id=session_id, keep_session=keep_session)
            except Exception as exc:  # a listener failure never blocks the revocation
                log.warning("revocation_listener_failed", exc_type=type(exc).__name__)

    async def revoke_session(self, session_id: UUID) -> None:
        try:
            await self._store.set(f"revoked:sid:{session_id}", "1", ex=self._ttl_s)
        except Exception as exc:
            log.warning("revocation_unavailable", exc_type=type(exc).__name__)
        await self._notify(session_id=session_id)

    async def revoke_user(self, user_id: UUID, *, keep_session: UUID | None = None) -> None:
        cutoff = str(int(self._clock() * 1000))
        try:
            await self._store.set(f"revoked:user:{user_id}", cutoff, ex=self._ttl_s)
            if keep_session is not None:
                await self._store.set(f"kept:sid:{keep_session}", cutoff, ex=self._ttl_s)
        except Exception as exc:
            log.warning("revocation_unavailable", exc_type=type(exc).__name__)
        await self._notify(user_id=user_id, keep_session=keep_session)

    async def is_revoked(self, claims: AccessClaims) -> bool:
        try:
            if await self._store.exists(f"revoked:sid:{claims.session_id}"):
                return True
            cutoff = await self._store.get(f"revoked:user:{claims.user_id}")
            if cutoff is None or claims.issued_at_ms > int(cutoff):
                return False
            kept = await self._store.get(f"kept:sid:{claims.session_id}")
        except Exception as exc:
            log.warning("revocation_unavailable", exc_type=type(exc).__name__)
            return False
        return bool(kept != cutoff)


async def current_user(
    request: Request,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> Principal:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise AppError(ErrorCode.UNAUTHENTICATED)
    tokens: TokenService = request.app.state.tokens
    try:
        claims = tokens.verify_access(credentials.credentials)
    except TokenError as exc:
        raise AppError(
            ErrorCode.TOKEN_EXPIRED if exc.expired else ErrorCode.UNAUTHENTICATED
        ) from None
    revocations: Revocations = request.app.state.revocations
    if await revocations.is_revoked(claims):
        raise AppError(ErrorCode.UNAUTHENTICATED)
    set_user_id(claims.user_id)
    # Global per-user limit (doc 07: 300/min/user) on top of the per-IP one in the middleware;
    # per-route policies (``user_limit``) apply after this.
    limiter: RateLimiter = request.app.state.rate_limiter
    await limiter.enforce("global_user", f"user:{claims.user_id}")
    return Principal(
        user_id=claims.user_id,
        role=claims.role,
        session_id=claims.session_id,
        tier_hint=claims.tier_hint,
    )


CurrentUser = Annotated[Principal, Depends(current_user)]


def require_role(*roles: str) -> Callable[[Principal], Awaitable[Principal]]:
    """Staff routes. A wrong role answers 404, like a missing object (no route probing)."""

    async def dependency(principal: CurrentUser) -> Principal:
        if principal.role not in roles:
            raise AppError(ErrorCode.NOT_FOUND)
        return principal

    return dependency


def require_staff(*roles: str) -> Callable[[Request, Principal], Awaitable[Principal]]:
    """Staff routes (/admin/*, doc 07 SEC-1.5): the role AND a client address inside
    STAFF_IP_ALLOWLIST. Either failure answers 404, like a missing route (no probing)."""

    async def dependency(request: Request, principal: CurrentUser) -> Principal:
        if principal.role not in roles:
            raise AppError(ErrorCode.NOT_FOUND)
        networks = [
            ipaddress.ip_network(cidr, strict=False)
            for cidr in request.app.state.settings.STAFF_IP_ALLOWLIST
        ]
        try:
            address = ipaddress.ip_address(client_ip(request.scope))
        except ValueError:
            raise AppError(ErrorCode.NOT_FOUND) from None
        if not any(address in network for network in networks):
            raise AppError(ErrorCode.NOT_FOUND)
        return principal

    return dependency


def user_limit(policy_name: str) -> Callable[[Request, Principal], Awaitable[None]]:
    """Per-user rate limit, evaluated after authentication."""
    policy = POLICIES[policy_name]

    async def dependency(request: Request, principal: CurrentUser) -> None:
        limiter: RateLimiter = request.app.state.rate_limiter
        await limiter.enforce(policy_name, f"user:{principal.user_id}", policy)

    return dependency
