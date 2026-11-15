"""In-process key/value store with expiry, used instead of Redis by the API (owner decision,
2026-11-03: no Redis until there are many users).

It implements only the calls the rate limiter, the access-token deny-list and the lockout-notice
dedupe make (``get``, ``set`` with ``ex``/``nx``, ``exists``, ``delete`` and a pipeline of ``incr``,
``expire``, ``pexpire``, ``get``), with the same reply shapes as ``redis.asyncio``, so Redis can be
put back later without touching those callers.

Scope: one API process. With several uvicorn workers or servers each keeps its own counters, so
limits become per process and a logout is only seen by the process that handled it until the
15-minute access token expires. Run a single worker until Redis returns.
"""

from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any

MAX_KEYS = 100_000  # bound memory: expired keys are swept once this many are held


class MemoryStore:
    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        self._clock = clock
        self._data: dict[str, tuple[str, float | None]] = {}

    def _alive(self, name: str) -> tuple[str, float | None] | None:
        item = self._data.get(name)
        if item is None:
            return None
        if item[1] is not None and item[1] <= self._clock():
            del self._data[name]
            return None
        return item

    def _sweep(self) -> None:
        if len(self._data) < MAX_KEYS:
            return
        now = self._clock()
        for key in [k for k, (_, exp) in self._data.items() if exp is not None and exp <= now]:
            del self._data[key]

    def _expiry(self, seconds: float | None) -> float | None:
        return None if seconds is None else self._clock() + seconds

    # --- the redis.asyncio subset (async, like the real client)
    async def get(self, name: str) -> bytes | None:
        return self._get(name)

    async def set(
        self, name: str, value: str, *, ex: int | None = None, nx: bool = False
    ) -> bool | None:
        return self._set(name, value, ex=ex, nx=nx)

    async def exists(self, *names: str) -> int:
        return sum(1 for n in names if self._alive(n) is not None)

    async def delete(self, *names: str) -> int:
        return sum(1 for n in names if self._data.pop(n, None) is not None)

    def pipeline(self, transaction: bool = True) -> MemoryPipeline:
        return MemoryPipeline(self)

    async def aclose(self) -> None:
        self._data.clear()

    # --- synchronous helpers shared with the pipeline
    def _get(self, name: str) -> bytes | None:
        item = self._alive(name)
        return None if item is None else item[0].encode()

    def _set(
        self, name: str, value: str, *, ex: float | None = None, nx: bool = False
    ) -> bool | None:
        if nx and self._alive(name) is not None:
            return None
        self._sweep()
        self._data[name] = (str(value), self._expiry(ex))
        return True

    def _incr(self, name: str, amount: int = 1) -> int:
        item = self._alive(name)
        value = (int(item[0]) if item else 0) + amount
        self._data[name] = (str(value), item[1] if item else None)
        return value

    def _expire(self, name: str, seconds: float) -> bool:
        item = self._alive(name)
        if item is None:
            return False
        self._data[name] = (item[0], self._expiry(seconds))
        return True


class MemoryPipeline:
    """Queues calls and runs them in order on ``execute`` (single process: nothing interleaves)."""

    def __init__(self, store: MemoryStore) -> None:
        self._store = store
        self._calls: list[Callable[[], Any]] = []

    def incr(self, name: str, amount: int = 1) -> MemoryPipeline:
        self._calls.append(lambda: self._store._incr(name, amount))
        return self

    def expire(self, name: str, time: int) -> MemoryPipeline:
        self._calls.append(lambda: self._store._expire(name, time))
        return self

    def pexpire(self, name: str, time: int) -> MemoryPipeline:
        self._calls.append(lambda: self._store._expire(name, time / 1000))
        return self

    def get(self, name: str) -> MemoryPipeline:
        self._calls.append(lambda: self._store._get(name))
        return self

    async def execute(self) -> list[object]:
        calls, self._calls = self._calls, []
        return [call() for call in calls]
