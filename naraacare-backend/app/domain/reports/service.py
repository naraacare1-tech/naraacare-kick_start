"""Streak and PDF reports for the API (doc 04 sections 2.7 and 2.11, Session 14).

* The database decides tier rules (custom range / sleep / insights), consent, the 10-a-day limit,
  idempotency and ownership; this layer shapes requests and responses.
* ``download_url`` is an API path (``/reports/{id}/file``) served behind the normal sign-in and an
  owner check: with no object store yet (no AWS, doc 03) there is no public URL that could leak.
  The app treats the URL as opaque, so a short-lived signed object-store URL can replace it later.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import date, datetime
from typing import Any
from uuid import UUID

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.integrations.storage import ObjectStorage
from app.repositories import report_repo
from app.repositories.base import Database


def _public(row: Mapping[str, Any], download_prefix: str) -> dict[str, Any]:
    ready = row["status"] == "ready" and row["storage_key"] is not None
    return {
        "report_id": row["report_id"],
        "type": row["kind"],
        "from": row["period_from"],
        "to": row["period_to"],
        "sections": list(row["sections"]),
        "status": row["status"],
        "size_bytes": row["size_bytes"] if ready else None,
        "created_at": row["created_at"],
        "expires_at": row["expires_at"] if ready else None,
        "download_url": f"{download_prefix}/reports/{row['report_id']}/file" if ready else None,
    }


class ReportService:
    def __init__(self, *, db: Database, storage: ObjectStorage, download_prefix: str) -> None:
        self.db = db
        self.storage = storage
        self.download_prefix = download_prefix

    async def streak(self, principal: Principal, month: date | None) -> dict[str, Any]:
        row = await self.db.run(
            lambda s: report_repo.streak(s, principal.user_id, month),
            user_id=principal.user_id,
            readonly=True,
        )
        active = set(row["active_days"] or [])
        today: date = row["today"]
        first = (month or today).replace(day=1)
        days = []
        current = first
        while current.month == first.month and current <= today:
            days.append({"date": current, "active": current in active})
            current = date.fromordinal(current.toordinal() + 1)
        week = [
            {"date": d, "active": d in active}
            for d in (date.fromordinal(today.toordinal() - i) for i in range(6, -1, -1))
        ]
        return {
            "current": row["current_streak"],
            "longest": row["longest_streak"],
            "broken_yesterday": row["broken_yesterday"],
            "today": today,
            "days": days,
            "last_7_days": week,
        }

    async def create(
        self, principal: Principal, idempotency_key: UUID, body: Mapping[str, Any]
    ) -> tuple[dict[str, Any], bool]:
        month: str | None = body.get("month")
        period_from = date.fromisoformat(f"{month}-01") if month else body.get("from_")
        row = await self.db.run(
            lambda s: report_repo.create_job(
                s,
                principal.user_id,
                idempotency_key=idempotency_key,
                kind=body["type"],
                period_from=period_from,
                period_to=body.get("to"),
                sections=body["sections"],
            ),
            user_id=principal.user_id,
        )
        return {"report_id": row["o_report_id"], "status": row["o_status"]}, bool(row["o_created"])

    async def list(
        self, principal: Principal, *, before: datetime | None, limit: int
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: report_repo.jobs(s, principal.user_id, before=before, limit=limit),
            user_id=principal.user_id,
            readonly=True,
        )
        next_before = rows[-1]["created_at"] if len(rows) == limit else None
        return {
            "items": [_public(r, self.download_prefix) for r in rows],
            "next_before": next_before,
        }

    async def _one(self, principal: Principal, report_id: UUID) -> Mapping[str, Any]:
        rows = await self.db.run(
            lambda s: report_repo.jobs(s, principal.user_id, report_id=report_id, limit=1),
            user_id=principal.user_id,
            readonly=True,
        )
        return rows[0]

    async def get(self, principal: Principal, report_id: UUID) -> dict[str, Any]:
        return _public(await self._one(principal, report_id), self.download_prefix)

    async def file(self, principal: Principal, report_id: UUID) -> tuple[bytes, Mapping[str, Any]]:
        row = await self._one(principal, report_id)
        key = row["storage_key"]
        if row["status"] != "ready" or key is None:
            raise AppError(ErrorCode.REPORT_NOT_READY)
        data = await self.storage.get(str(key))
        if data is None:
            raise AppError(ErrorCode.NOT_FOUND)
        return data, row
