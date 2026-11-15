"""Reminder push jobs (Session 09 step 7). Run by the taskiq scheduler only: no route can trigger
them, and the database functions they call are granted to the worker role alone.

* ``send_reminders`` (every minute): ``ops.fn_due_reminders`` -> one push per device.
* ``day_ending_soon`` (every 15 minutes): ``ops.fn_day_ending_soon`` -> one nudge per device.
* At-least-once delivery: a Redis ``SET NX`` key per user, type and slot (kept 2 h) makes a
  redelivered job send nothing twice.
* Push texts are the fixed templates in ``app.integrations.fcm`` (no health values, OQ-41). Tokens
  are stored in plain text; tokens FCM reports as unregistered are wiped.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import UTC, datetime
from decimal import Decimal
from typing import Any, Protocol
from uuid import UUID

import structlog

from app.integrations.fcm import TEMPLATES, PushMessage, PushResult
from app.repositories import notify_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)

DEDUP_TTL_S = 2 * 3600


class Sender(Protocol):
    async def send(self, token: str, message: PushMessage) -> PushResult: ...


class Dedup(Protocol):
    def set(self, name: str, value: str, *, nx: bool, ex: int) -> Awaitable[Any]: ...


@dataclass(slots=True)
class PushStats:
    sent: int = 0
    skipped: int = 0
    dead: int = 0
    failed: int = 0


async def _fan_out(
    *,
    db: Database,
    sender: Sender,
    dedup: Dedup,
    rows: Sequence[Mapping[str, Any]],
    kind_of: Any,
    slot: str,
) -> PushStats:
    stats = PushStats()
    dead: list[UUID] = []
    for row in rows:
        kind = kind_of(row)
        key = f"push:{kind}:{row['user_id']}:{row['device_id']}:{slot}"
        if not await dedup.set(key, "1", nx=True, ex=DEDUP_TTL_S):
            stats.skipped += 1
            continue
        result = await sender.send(str(row["push_token"]), TEMPLATES[kind])
        if result is PushResult.SENT:
            stats.sent += 1
        elif result is PushResult.DEAD_TOKEN:
            stats.dead += 1
            dead.append(row["device_id"])
        else:
            stats.failed += 1
    for device_id in dead:
        await db.run(_revoker(device_id))
    return stats


def _revoker(device_id: UUID) -> Callable[[DbSession], Awaitable[None]]:
    async def revoke(session: DbSession) -> None:
        await notify_repo.revoke_push_token(session, device_id)

    return revoke


async def send_reminders(
    *, db: Database, sender: Sender, dedup: Dedup, now: datetime | None = None
) -> PushStats:
    moment = (now or datetime.now(UTC)).replace(second=0, microsecond=0)
    rows = await db.run(lambda s: notify_repo.due_reminders(s, moment))
    stats = await _fan_out(
        db=db,
        sender=sender,
        dedup=dedup,
        rows=rows,
        kind_of=lambda r: r["reminder_type"],
        slot=moment.strftime("%Y%m%d%H%M"),
    )
    log.info(
        "reminders_sent",
        sent=stats.sent,
        skipped=stats.skipped,
        dead=stats.dead,
        failed=stats.failed,
    )
    return stats


async def day_ending_soon(
    *,
    db: Database,
    sender: Sender,
    dedup: Dedup,
    hours: Decimal,
    window_min: int = 15,
    now: datetime | None = None,
) -> PushStats:
    moment = (now or datetime.now(UTC)).replace(second=0, microsecond=0)
    rows = await db.run(lambda s: notify_repo.day_ending_soon(s, moment, hours, window_min))
    stats = await _fan_out(
        db=db,
        sender=sender,
        dedup=dedup,
        rows=rows,
        kind_of=lambda _r: "day_ending_soon",
        slot=moment.strftime("%Y%m%d"),  # once per device per UTC day
    )
    log.info("day_ending_soon_sent", sent=stats.sent, skipped=stats.skipped, dead=stats.dead)
    return stats
