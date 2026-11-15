"""Social push job (Session 12). Run by the taskiq scheduler only (every minute); the database
function it reads is granted to the worker role alone.

* ``ops.fn_social_pushes`` returns the in-app social notifications created since the last run,
  one row per device, already filtered by the per-circle switches, the global toggles and quiet
  hours.
* A cursor in Redis (the worker's own) remembers where the last run stopped; without one the job
  looks back 2 minutes. Runs read up to 5 s before "now" so rows still being committed are not
  skipped.
* At-least-once delivery: a ``SET NX`` key per notification and device (kept 1 day) makes a
  redelivered job or an overlapping window send nothing twice.
* Push texts are the fixed templates in ``app.integrations.fcm.SOCIAL_TEMPLATES``: no message text,
  no names, no health values (OQ-41). Unknown template codes are skipped.
"""

from __future__ import annotations

import dataclasses
from collections.abc import Awaitable
from datetime import UTC, datetime, timedelta
from typing import Any, Protocol
from uuid import UUID

import structlog

from app.integrations.fcm import SOCIAL_TEMPLATES, PushResult
from app.repositories import notify_repo
from app.repositories.base import Database
from app.workers.jobs.reminders import PushStats, Sender, _revoker

log = structlog.get_logger(__name__)

CURSOR_KEY = "push:social:cursor"
DEDUP_TTL_S = 24 * 3600
LOOKBACK = timedelta(minutes=2)
SETTLE = timedelta(seconds=5)
BATCH = 2000


class Store(Protocol):
    def get(self, name: str) -> Awaitable[Any]: ...
    def set(
        self, name: str, value: str, *, nx: bool = False, ex: int | None = None
    ) -> Awaitable[Any]: ...


async def send_social_pushes(
    *, db: Database, sender: Sender, store: Store, now: datetime | None = None
) -> PushStats:
    until = (now or datetime.now(UTC)) - SETTLE
    raw = await store.get(CURSOR_KEY)
    after = (
        datetime.fromisoformat(raw.decode() if isinstance(raw, bytes) else str(raw))
        if raw
        else until - LOOKBACK
    )
    rows = await db.run(lambda s: notify_repo.social_pushes(s, after, until, BATCH))
    stats = PushStats()
    dead: list[UUID] = []
    for row in rows:
        template = SOCIAL_TEMPLATES.get(str(row["template_code"]))
        if template is None:
            stats.skipped += 1
            continue
        key = f"push:n:{row['notification_id']}:{row['device_id']}"
        if not await store.set(key, "1", nx=True, ex=DEDUP_TTL_S):
            stats.skipped += 1
            continue
        message = dataclasses.replace(template, deep_link=row["deep_link"] or template.deep_link)
        result = await sender.send(str(row["push_token"]), message)
        if result is PushResult.SENT:
            stats.sent += 1
        elif result is PushResult.DEAD_TOKEN:
            stats.dead += 1
            dead.append(row["device_id"])
        else:
            stats.failed += 1
    for device_id in dead:
        await db.run(_revoker(device_id))
    # A full batch may stop inside one timestamp: step back 1 microsecond so the next run sees the
    # rest (repeats are caught by the NX keys).
    next_cursor = (
        rows[-1]["created_at"] - timedelta(microseconds=1) if len(rows) == BATCH else until
    )
    await store.set(CURSOR_KEY, next_cursor.isoformat())
    log.info(
        "social_pushes_sent",
        sent=stats.sent,
        skipped=stats.skipped,
        dead=stats.dead,
        failed=stats.failed,
    )
    return stats
