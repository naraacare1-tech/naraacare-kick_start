"""Privacy jobs (Session 15, doc 07 SEC-7, doc 05 section 9). Run by the taskiq scheduler only; the
``ops`` functions they call are granted to the worker role alone. Nothing personal is logged: ids
and counts only.

* ``generate_exports`` (every minute): claims export requests, reads all of the user's rows
  (``ops.fn_export_user``), builds the ZIP and stores it under a random key; the database marks it
  ready for 7 days and notifies the user. Failures are retried up to 3 times.
* ``expire_exports`` (hourly): files of exports older than 7 days are deleted.
* ``process_deletions`` (hourly): for each account whose 30-day grace is over: revoke Sign in with
  Apple (App Store rule), delete stored files (reports, screenshots, exports), send the receipt to
  the address captured just before erasure (once), then ``ops.pr_delete_user``. A failure leaves
  the request scheduled, so the next run tries again.
* ``apply_retention`` (daily): partitions past retention are dropped, rows past
  ``privacy.retention_policy`` purged, old support screenshots deleted; the counts are logged as the
  monitoring metric.
"""

from __future__ import annotations

import dataclasses
from datetime import UTC, datetime
from functools import partial
from typing import Protocol
from uuid import UUID

import structlog

from app.domain.privacy.export import build_zip
from app.integrations.email import EmailSender, send_quietly
from app.integrations.storage import ObjectStorage, new_key
from app.repositories import privacy_repo
from app.repositories.base import Database

log = structlog.get_logger(__name__)

EXPORT_BATCH = 2
DELETION_BATCH = 20


class AppleRevoker(Protocol):
    async def revoke(self, refresh_token: str) -> bool: ...


@dataclasses.dataclass(slots=True)
class JobStats:
    done: int = 0
    failed: int = 0


async def generate_exports(*, db: Database, storage: ObjectStorage) -> JobStats:
    stats = JobStats()
    for job in await db.run(lambda s: privacy_repo.claim_exports(s, EXPORT_BATCH)):
        export_id: UUID = job["export_id"]
        user_id: UUID = job["user_id"]
        try:
            data = await db.run(partial(privacy_repo.export_user, user_id=user_id))
            archive = build_zip(data, datetime.now(UTC))
            key = new_key("exports", "zip")
            await storage.put(key, archive)
            await db.run(
                partial(
                    privacy_repo.finish_export,
                    export_id=export_id,
                    ok=True,
                    object_key=key,
                    size_bytes=len(archive),
                )
            )
            stats.done += 1
            log.info("export_built", export_id=str(export_id), size_bytes=len(archive))
        except Exception as exc:  # one bad export never stops the batch
            stats.failed += 1
            log.warning("export_failed", export_id=str(export_id), error=type(exc).__name__)
            await db.run(
                partial(
                    privacy_repo.finish_export,
                    export_id=export_id,
                    ok=False,
                    error_code="build_failed",
                )
            )
    return stats


async def expire_exports(*, db: Database, storage: ObjectStorage) -> int:
    rows = await db.run(lambda s: privacy_repo.expire_exports(s, 500))
    for row in rows:
        if row["object_key"]:
            await storage.delete(str(row["object_key"]))
    return len(rows)


async def process_deletions(
    *,
    db: Database,
    storage: ObjectStorage,
    email: EmailSender,
    apple: AppleRevoker | None,
) -> JobStats:
    stats = JobStats()
    for due in await db.run(lambda s: privacy_repo.due_deletions(s, DELETION_BATCH)):
        user_id: UUID = due["user_id"]
        try:
            token = due["apple_refresh_token"]
            if token and apple is not None and not await apple.revoke(str(token)):
                log.warning("deletion_apple_revoke_failed", user_id=str(user_id))
            for key in await db.run(partial(privacy_repo.user_files, user_id=user_id)):
                await storage.delete(key)
            if not due["receipt_sent"]:
                await send_quietly(email, str(due["email"]), "deletion_completed", {})
                await db.run(partial(privacy_repo.mark_receipt, user_id=user_id))
            archived = await db.run(partial(privacy_repo.delete_user, user_id=user_id))
            stats.done += 1
            log.info("account_erased", rows_archived=archived)
        except Exception as exc:  # stays scheduled; retried next run
            stats.failed += 1
            log.warning("account_erasure_failed", user_id=str(user_id), error=type(exc).__name__)
    return stats


async def apply_retention(*, db: Database, storage: ObjectStorage) -> dict[str, int]:
    counts = await db.run(privacy_repo.apply_retention)
    keys = await db.run(lambda s: privacy_repo.expired_attachments(s, 500))
    for key in keys:
        await storage.delete(key)
    counts["support.attachment"] = len(keys)
    log.info("retention_applied", **counts)
    return counts
