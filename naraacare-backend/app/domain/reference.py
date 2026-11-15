"""Reference data held in memory for a short time (it changes only with deployments/seeds).

* calculation context (``ref.fn_calc_context``) for the calculators and code checks;
* the public bootstrap payload + ETag (``ref.fn_bootstrap``) for GET /reference/bootstrap.
Both are refreshed after ``TTL_S``; a failed refresh keeps serving the previous copy.
"""

from __future__ import annotations

import json
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import anyio
import structlog

from app.domain.common.calc_context import CalcContext
from app.repositories import reference_repo
from app.repositories.base import Database

log = structlog.get_logger(__name__)

TTL_S = 300


@dataclass(frozen=True, slots=True)
class Bootstrap:
    etag: str
    payload: dict[str, Any]


class ReferenceCache:
    def __init__(self, db: Database, clock: Callable[[], float] = time.monotonic) -> None:
        self._db = db
        self._clock = clock
        self._lock = anyio.Lock()
        self._context: CalcContext | None = None
        self._context_at = 0.0
        self._bootstrap: Bootstrap | None = None
        self._bootstrap_at = 0.0

    def _fresh(self, loaded_at: float) -> bool:
        return self._clock() - loaded_at < TTL_S

    async def calc_context(self) -> CalcContext:
        if self._context is not None and self._fresh(self._context_at):
            return self._context
        async with self._lock:
            if self._context is None or not self._fresh(self._context_at):
                raw = await self._db.run(reference_repo.calc_context, readonly=True)
                self._context = CalcContext.from_db(raw)
                self._context_at = self._clock()
        return self._context

    async def bootstrap(self) -> Bootstrap:
        if self._bootstrap is not None and self._fresh(self._bootstrap_at):
            return self._bootstrap
        async with self._lock:
            if self._bootstrap is None or not self._fresh(self._bootstrap_at):
                row = await self._db.run(reference_repo.bootstrap, readonly=True)
                payload = row["payload"]
                self._bootstrap = Bootstrap(
                    etag=str(row["etag"]),
                    payload=json.loads(payload) if isinstance(payload, str) else dict(payload),
                )
                self._bootstrap_at = self._clock()
        return self._bootstrap
