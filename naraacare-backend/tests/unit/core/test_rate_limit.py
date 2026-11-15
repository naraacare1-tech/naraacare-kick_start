"""Sliding-window rate limiter and penalty box (doc 07 §4.4, §5)."""

from __future__ import annotations

import pytest

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.memory_store import MemoryStore
from app.middleware.rate_limit import (
    ALERT_THRESHOLD,
    PENALTY_THRESHOLD,
    POLICIES,
    KeyBy,
    Policy,
    RateLimiter,
    rate_limit,
)


class Clock:
    def __init__(self, now: float) -> None:
        self.now = now

    def __call__(self) -> float:
        return self.now


@pytest.fixture
def clock() -> Clock:
    return Clock(60 * 16_667 + 20.0)  # 20 s into a 60 s window


@pytest.fixture
def limiter(clock: Clock) -> RateLimiter:
    return RateLimiter(MemoryStore(), clock=clock)


POLICY = Policy(limit=5, window_s=60, key_by=KeyBy.IP)


async def test_allows_up_to_the_limit_then_blocks(limiter: RateLimiter) -> None:
    results = [await limiter.hit("t", "ip:1", POLICY) for _ in range(6)]
    assert [r.allowed for r in results] == [True] * 5 + [False]
    assert results[-1].retry_after_s == 40  # rest of the current window


async def test_principals_are_independent(limiter: RateLimiter) -> None:
    for _ in range(5):
        await limiter.hit("t", "ip:1", POLICY)
    assert (await limiter.hit("t", "ip:2", POLICY)).allowed


async def test_previous_window_still_counts_while_it_overlaps(
    limiter: RateLimiter, clock: Clock
) -> None:
    for _ in range(5):
        await limiter.hit("t", "ip:1", POLICY)
    clock.now += 45  # 5 s into the next window: 55/60 of the previous one still overlaps
    assert not (await limiter.hit("t", "ip:1", POLICY)).allowed
    clock.now += 60  # two windows later: free again
    assert (await limiter.hit("t", "ip:1", POLICY)).allowed


async def test_enforce_raises_rate_limited_with_retry_after(limiter: RateLimiter) -> None:
    policy = Policy(limit=1, window_s=60, key_by=KeyBy.IP)
    await limiter.enforce("t", "ip:1", policy)
    with pytest.raises(AppError) as info:
        await limiter.enforce("t", "ip:1", policy)
    assert info.value.code is ErrorCode.RATE_LIMITED
    assert info.value.headers["Retry-After"] == "40"


async def test_penalty_box_after_ten_rejections_and_single_alert(limiter: RateLimiter) -> None:
    for _ in range(PENALTY_THRESHOLD - 1):
        assert not await limiter.record_unsafe_rejection("ip:1")
    assert not await limiter.in_penalty_box("ip:1")
    await limiter.record_unsafe_rejection("ip:1")
    assert await limiter.in_penalty_box("ip:1")
    alerts = [await limiter.record_unsafe_rejection("ip:1") for _ in range(ALERT_THRESHOLD)]
    assert alerts.count(True) == 1  # one alert per principal per hour


class BrokenRedis:
    def pipeline(self, transaction: bool = True) -> object:
        raise ConnectionError("redis down")

    async def exists(self, *names: str) -> int:
        raise ConnectionError("redis down")

    async def set(self, *args: object, **kwargs: object) -> object:
        raise ConnectionError("redis down")


async def test_fails_open_when_redis_is_down() -> None:
    limiter = RateLimiter(BrokenRedis())  # type: ignore[arg-type]
    assert (await limiter.hit("t", "ip:1", POLICY)).allowed
    assert not await limiter.in_penalty_box("ip:1")
    assert not await limiter.record_unsafe_rejection("ip:1")


def test_policies_cover_doc_04_routes() -> None:
    assert POLICIES["auth_login"] == Policy(10, 60, KeyBy.IP)
    assert POLICIES["global_ip"].limit == 600
    assert POLICIES["global_user"].limit == 300
    assert POLICIES["auth_signup_ip"] == Policy(5, 3600, KeyBy.IP)


def test_custom_keyed_policies_cannot_be_used_as_dependencies() -> None:
    with pytest.raises(ValueError, match="caller-supplied principal"):
        rate_limit("auth_signup_email")
