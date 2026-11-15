"""GET /sync/changes (doc 04 section 2.14, doc 03 section 3.1, Session 14).

* Returns the caller's meals, intakes, workouts and sleep entries changed after the cursor (oldest
  first, at most 500 a page), with deleted rows as ``deleted_ids``. Only the caller's rows: the
  database function asserts the actor and RLS applies.
* The cursor is opaque to the app: base64url of ``{"t": updated_at, "i": id}`` of the last row sent.
  It carries no secret (it only says "after this change of yours"), and a cursor that does not parse
  is rejected as invalid input, never trusted.
"""

from __future__ import annotations

import base64
import binascii
import json
from collections.abc import Mapping
from datetime import datetime
from typing import Any
from uuid import UUID

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.repositories import support_repo
from app.repositories.base import Database

PAGE = 500
KIND_KEYS = {"meal": "meals", "intake": "intakes", "workout": "workouts", "sleep": "sleep_entries"}


def encode_cursor(at: datetime, item_id: UUID) -> str:
    raw = json.dumps({"t": at.isoformat(), "i": str(item_id)}, separators=(",", ":"))
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, UUID]:
    try:
        raw = base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4))
        data = json.loads(raw)
        at = datetime.fromisoformat(data["t"])
        if at.tzinfo is None:
            raise ValueError("naive")
        return at, UUID(data["i"])
    except (binascii.Error, ValueError, KeyError, TypeError) as exc:
        raise AppError(ErrorCode.VALIDATION_FAILED, fields=["since"]) from exc


def _item(row: Mapping[str, Any]) -> dict[str, Any]:
    data = row["data"]
    payload = json.loads(data) if isinstance(data, str | bytes) else dict(data)
    return {
        "id": row["id"],
        "local_date": row["local_date"],
        "version": row["version"],
        "updated_at": row["updated_at"],
        **payload,
    }


class SyncService:
    def __init__(self, *, db: Database) -> None:
        self.db = db

    async def changes(self, principal: Principal, since: str | None) -> dict[str, Any]:
        after_at, after_id = decode_cursor(since) if since else (None, None)
        rows = await self.db.run(
            lambda s: support_repo.changes(
                s, principal.user_id, after_at=after_at, after_id=after_id, limit=PAGE + 1
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        has_more = len(rows) > PAGE
        rows = rows[:PAGE]
        result: dict[str, Any] = {key: [] for key in KIND_KEYS.values()}
        result["deleted_ids"] = []
        for row in rows:
            if row["deleted"]:
                result["deleted_ids"].append(row["id"])
            else:
                result[KIND_KEYS[row["kind"]]].append(_item(row))
        last = rows[-1] if rows else None
        result["next_cursor"] = (
            encode_cursor(last["updated_at"], last["id"]) if last is not None else since
        )
        result["has_more"] = has_more
        return result
