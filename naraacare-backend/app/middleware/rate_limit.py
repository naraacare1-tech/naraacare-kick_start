"""Rate limiting (doc 04 §2 Rate column, doc 07 §5 and §4.4 abuse rules).

Algorithm: sliding-window counter in the API's in-process store (``app.core.memory_store``; Redis
is not used until there are many users). Two fixed-window counters (current and previous) are
combined, weighting the previous one by how much of it still overlaps the sliding window. It is
O(1) memory per principal (one INCR + one GET per request), unlike a sorted-set log, which
matters at 600 req/min/IP. Accuracy is within a few percent of an exact sliding log, which is
enough for abuse limits.

Layers:
* ``RateLimitMiddleware``: global per-IP limit (600/min) for every request, tightened to 10/min for
  15 minutes while the IP is in the penalty box.
* ``rate_limit(policy)`` route dependency: the per-route policies (auth flows, writes, search) and
  the per-user global limit; keyed by the authenticated user, else by IP.
* Penalty box: >= 10 unsafe-input rejections in 10 min puts the principal on 10 req/min for 15 min;
  >= 50 in an hour raises a ``security_alert``.

Keys hold the principal as is (``ip:<addr>``, ``user:<id>``, an email); the store lives only in
memory. If the store ever fails the limiter fails OPEN and logs ``rate_limit_unavailable``:
availability wins here, because account-level protections (lockout, OTP attempt limits) live in the
database regardless. Limits are per API process (see the memory store's docstring).
"""

from __future__ import annotations

import ipaddress
import math
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from enum import StrEnum
from typing import Any, Protocol

import structlog
from fastapi import Request
from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError, error_response
from app.core.security.request_context import current_user_id

log = structlog.get_logger(__name__)


class KeyBy(StrEnum):
    IP = "ip"
    USER = "user"  # authenticated user, falling back to IP before sign-in
    CUSTOM = "custom"  # the caller passes the principal, e.g. an email (Session 05)


@dataclass(frozen=True, slots=True)
class Policy:
    limit: int
    window_s: int
    key_by: KeyBy


POLICIES: dict[str, Policy] = {
    "global_ip": Policy(600, 60, KeyBy.IP),
    "global_user": Policy(300, 60, KeyBy.USER),
    "penalty": Policy(10, 60, KeyBy.IP),
    "auth_signup_ip": Policy(5, 3600, KeyBy.IP),
    "auth_signup_email": Policy(3, 3600, KeyBy.CUSTOM),
    "auth_login": Policy(10, 60, KeyBy.IP),
    "auth_login_account": Policy(5, 900, KeyBy.CUSTOM),
    "auth_otp_verify": Policy(10, 60, KeyBy.IP),
    "auth_otp_resend": Policy(5, 3600, KeyBy.IP),
    "auth_oauth": Policy(10, 60, KeyBy.IP),
    "auth_link": Policy(5, 900, KeyBy.IP),
    "auth_refresh": Policy(30, 60, KeyBy.IP),
    "auth_password_forgot": Policy(10, 3600, KeyBy.IP),
    "auth_password_forgot_email": Policy(3, 3600, KeyBy.CUSTOM),
    "auth_password_reset": Policy(10, 3600, KeyBy.IP),
    "auth_password_change": Policy(5, 3600, KeyBy.USER),
    "consents": Policy(20, 3600, KeyBy.USER),
    "username_availability": Policy(30, 60, KeyBy.USER),
    "writes": Policy(60, 60, KeyBy.USER),
    "search": Policy(30, 60, KeyBy.USER),
    "barcode": Policy(30, 60, KeyBy.USER),
    "voice_parse": Policy(20, 60, KeyBy.USER),
    "staff_writes": Policy(60, 60, KeyBy.USER),
    "drink_estimate": Policy(10, 60, KeyBy.USER),
    "devices": Policy(20, 3600, KeyBy.USER),
    "purchase_verify": Policy(10, 60, KeyBy.USER),
    "people_search": Policy(30, 60, KeyBy.USER),
    "chat": Policy(30, 60, KeyBy.USER),
    "invite_resolve": Policy(10, 60, KeyBy.USER),  # slows guessing of invite tokens
    "realtime_ticket": Policy(20, 60, KeyBy.USER),
    "rin_chat": Policy(20, 60, KeyBy.USER),  # on top of the daily token allowance
    # S14: bursts only; the daily caps (10 reports, 5 tickets / requests) live in the database.
    "reports": Policy(5, 60, KeyBy.USER),
    "support": Policy(3, 60, KeyBy.USER),
    # S15: re-auth, export and deletion (password guessing is also capped by the login lockout).
    "privacy_sensitive": Policy(5, 900, KeyBy.USER),
}
PENALTY_THRESHOLD = 10
PENALTY_WINDOW_S = 600
PENALTY_DURATION_S = 900
ALERT_THRESHOLD = 50
ALERT_WINDOW_S = 3600


class StoreLike(Protocol):
    """The subset of redis.asyncio.Redis used here (``MemoryStore`` implements it)."""

    def pipeline(self, transaction: bool = True) -> Pipeline: ...
    def exists(self, *names: str) -> Awaitable[int]: ...
    def set(
        self, name: str, value: str, *, ex: int | None = None, nx: bool = False
    ) -> Awaitable[Any]: ...


class Pipeline(Protocol):
    def incr(self, name: str, amount: int = 1) -> object: ...
    def pexpire(self, name: str, time: int) -> object: ...
    def expire(self, name: str, time: int) -> object: ...
    def get(self, name: str) -> object: ...
    async def execute(self) -> list[object]: ...


def _as_int(value: object) -> int:
    """Store replies are bytes or int (or None for a missing key)."""
    if value is None:
        return 0
    if isinstance(value, bytes | str | int):
        return int(value)
    raise TypeError("unexpected store reply")


@dataclass(frozen=True, slots=True)
class Decision:
    allowed: bool
    retry_after_s: int = 0


class RateLimiter:
    def __init__(self, store: StoreLike, clock: Callable[[], float] = time.time) -> None:
        self.store = store
        self.clock = clock

    async def hit(self, name: str, principal: str, policy: Policy) -> Decision:
        window_ms = policy.window_s * 1000
        now_ms = int(self.clock() * 1000)
        bucket = now_ms // window_ms
        elapsed = now_ms - bucket * window_ms
        key = f"rl:{name}:{principal}"
        try:
            pipe = self.store.pipeline(transaction=False)
            pipe.incr(f"{key}:{bucket}")
            pipe.pexpire(f"{key}:{bucket}", window_ms * 2)
            pipe.get(f"{key}:{bucket - 1}")
            current, _, previous = await pipe.execute()
        except Exception as exc:  # fail open on any store failure, see module docstring
            log.warning("rate_limit_unavailable", exc_type=type(exc).__name__)
            return Decision(allowed=True)
        weight = (window_ms - elapsed) / window_ms
        count = _as_int(current) + _as_int(previous) * weight
        if count <= policy.limit:
            return Decision(allowed=True)
        return Decision(
            allowed=False, retry_after_s=max(1, math.ceil((window_ms - elapsed) / 1000))
        )

    async def enforce(self, name: str, principal: str, policy: Policy | None = None) -> None:
        decision = await self.hit(name, principal, policy or POLICIES[name])
        if not decision.allowed:
            log.info("rate_limited", policy=name)
            raise AppError(
                ErrorCode.RATE_LIMITED,
                extra={"retry_after_s": decision.retry_after_s},
                headers={"Retry-After": str(decision.retry_after_s)},
            )

    async def in_penalty_box(self, principal: str) -> bool:
        try:
            return bool(await self.store.exists(f"penalty:{principal}"))
        except Exception as exc:
            log.warning("rate_limit_unavailable", exc_type=type(exc).__name__)
            return False

    async def record_unsafe_rejection(self, principal: str) -> bool:
        """Count an unsafe-input rejection. Returns True when the alert threshold is crossed."""
        key = principal
        try:
            pipe = self.store.pipeline(transaction=False)
            pipe.incr(f"rej10m:{key}")
            pipe.expire(f"rej10m:{key}", PENALTY_WINDOW_S)
            pipe.incr(f"rej1h:{key}")
            pipe.expire(f"rej1h:{key}", ALERT_WINDOW_S)
            short, _, long, _ = await pipe.execute()
            if _as_int(short) >= PENALTY_THRESHOLD:
                await self.store.set(f"penalty:{key}", "1", ex=PENALTY_DURATION_S)
            if _as_int(long) >= ALERT_THRESHOLD:
                # NX: one alert per principal per hour, not one per rejection.
                return bool(await self.store.set(f"alerted:{key}", "1", ex=ALERT_WINDOW_S, nx=True))
        except Exception as exc:
            log.warning("rate_limit_unavailable", exc_type=type(exc).__name__)
        return False


def client_ip(scope: Scope) -> str:
    """Peer address. Behind the load balancer, uvicorn runs with --proxy-headers and
    --forwarded-allow-ips set to the load balancer's addresses, so this is the real client and
    X-Forwarded-For cannot be spoofed."""
    client = scope.get("client")
    return str(client[0]) if client else "unknown"


def client_ip_or_none(scope: Scope) -> str | None:
    """The peer address when it is a real IP (stored as ``inet``); None otherwise."""
    ip = client_ip(scope)
    try:
        ipaddress.ip_address(ip)
    except ValueError:
        return None
    return ip


def principal_for(request: Request, key_by: KeyBy) -> str:
    user_id = current_user_id()
    if key_by is KeyBy.USER and user_id is not None:
        return f"user:{user_id}"
    return f"ip:{client_ip(request.scope)}"


def rate_limit(policy_name: str) -> Callable[[Request], Awaitable[None]]:
    """Route dependency: ``dependencies=[Depends(rate_limit("auth_login"))]``."""
    policy = POLICIES[policy_name]
    if policy.key_by is KeyBy.CUSTOM:
        raise ValueError(
            f"{policy_name} needs a caller-supplied principal; use RateLimiter.enforce"
        )

    async def dependency(request: Request) -> None:
        limiter: RateLimiter = request.app.state.rate_limiter
        principal = principal_for(request, policy.key_by)
        if await limiter.in_penalty_box(principal):
            await limiter.enforce("penalty", principal)
        await limiter.enforce(policy_name, principal, policy)

    return dependency


class RateLimitMiddleware:
    def __init__(self, app: ASGIApp, *, limiter_from_state: str = "rate_limiter") -> None:
        self.app = app
        self.state_key = limiter_from_state

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limiter: RateLimiter | None = getattr(scope["app"].state, self.state_key, None)
        if limiter is not None:
            principal = f"ip:{client_ip(scope)}"
            try:
                if await limiter.in_penalty_box(principal):
                    await limiter.enforce("penalty", principal)
                await limiter.enforce("global_ip", principal)
            except AppError as exc:
                response = error_response(exc.code, extra=exc.extra, headers=exc.headers)
                await response(scope, receive, send)
                return
        await self.app(scope, receive, send)
