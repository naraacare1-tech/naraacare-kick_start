"""Security events (doc 07 §4.4): written asynchronously through audit.pr_log_security_event.

Requests never wait for the audit write: events go into a bounded in-process queue and one
background task writes them. When the queue is full (database down, flood) events are dropped and
counted in the log rather than slowing every request. Details hold only numbers, booleans and
machine codes, which the database procedure enforces too; rejected payloads are never included.
"""

from __future__ import annotations

import asyncio
import contextlib
import json
from dataclasses import dataclass, field
from uuid import UUID

import regex
import structlog

from app.repositories.base import Database, db_call

log = structlog.get_logger(__name__)

LOG_SECURITY_EVENT = db_call(
    "CALL audit.pr_log_security_event("
    ":event_type, :user_id, CAST(:ip AS inet), :request_id, :field_name, :details)"
)
_CODE_UNSAFE = regex.compile(r"[^a-z0-9_.]")


def as_code(value: str) -> str:
    """Field names/labels in common.code format (lower snake case, dots allowed, max 63)."""
    cleaned = _CODE_UNSAFE.sub("_", value.lower()).strip("_.") or "field"
    return (cleaned if cleaned[0].isalpha() else f"f_{cleaned}")[:63]


@dataclass(frozen=True, slots=True)
class SecurityEvent:
    event_type: str
    user_id: UUID | None = None
    ip: str | None = None
    request_id: UUID | None = None
    field_name: str | None = None
    details: dict[str, int | float | bool | str | None] = field(default_factory=dict)


class SecurityEventWriter:
    def __init__(self, db: Database, *, max_queue: int = 1000) -> None:
        self._db = db
        self._queue: asyncio.Queue[SecurityEvent] = asyncio.Queue(maxsize=max_queue)
        self._task: asyncio.Task[None] | None = None
        self.dropped = 0

    def submit(self, event: SecurityEvent) -> None:
        try:
            self._queue.put_nowait(event)
        except asyncio.QueueFull:
            self.dropped += 1
            log.warning("security_event_dropped", dropped_total=self.dropped)

    async def _write(self, event: SecurityEvent) -> None:
        async with self._db.transaction() as session:
            await session.execute(
                LOG_SECURITY_EVENT,
                event_type=event.event_type,
                user_id=event.user_id,
                ip=event.ip,
                request_id=event.request_id,
                field_name=as_code(event.field_name) if event.field_name else None,
                details=json.dumps(event.details),
            )

    async def _run(self) -> None:
        while True:
            event = await self._queue.get()
            try:
                await self._write(event)
            except Exception as exc:  # the writer must survive any single failure
                log.warning("security_event_write_failed", exc_type=type(exc).__name__)
            finally:
                self._queue.task_done()

    def start(self) -> None:
        self._task = asyncio.create_task(self._run(), name="security-event-writer")

    async def stop(self, timeout_s: float = 5.0) -> None:
        """Flush what is queued (bounded wait), then stop."""
        with contextlib.suppress(TimeoutError):
            await asyncio.wait_for(self._queue.join(), timeout_s)
        if self._task is not None:
            self._task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self._task
