"""Sleep tracking (doc 04 section 2.6, doc 06 section 4, Session 10). STAR only.

* The database computes counted minutes (buffers and night wakings), the daily total, score and
  label from the calc constants, and enforces the STAR gate, the 16 h limit, overlap (exclusion
  constraint) and the edit window. This layer checks the entitlement first so a 403 carries
  ``feature``, and adds the server copy as ``current`` on 409 VERSION_CONFLICT.
* ``PUT /me/sleep-goal`` is allowed on every tier (the goal is profile data); reading sleep is STAR.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import date
from typing import Any
from uuid import UUID

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain.entitlements.service import EntitlementService
from app.repositories import sleep_repo
from app.repositories.base import Database, DbSession

FEATURE = "sleep"


class SleepService:
    def __init__(self, *, db: Database, entitlements: EntitlementService) -> None:
        self.db = db
        self.entitlements = entitlements

    async def _require(self, principal: Principal) -> None:
        entitlement = await self.entitlements.get(principal.user_id)
        if not entitlement.allows(FEATURE):
            raise AppError(ErrorCode.UPGRADE_REQUIRED, extra={"feature": FEATURE})

    async def summary(self, principal: Principal, on_date: date | None) -> dict[str, Any]:
        await self._require(principal)
        return await self.db.run(
            lambda s: sleep_repo.summary(s, principal.user_id, on_date),
            user_id=principal.user_id,
            readonly=True,
        )

    async def log_entry(
        self, principal: Principal, body: Mapping[str, Any]
    ) -> tuple[bool, dict[str, Any]]:
        """(created, {entry, summary}); a replay of the same client_entry_id returns the stored
        entry with created = False (offline sync)."""
        await self._require(principal)
        entry_id: UUID = body["client_entry_id"]

        async def work(s: DbSession) -> tuple[str, dict[str, Any], dict[str, Any]]:
            status, local_date = await sleep_repo.log_entry(
                s,
                principal.user_id,
                entry_id=entry_id,
                sleep_start=body["sleep_start"],
                wake_time=body["wake_time"],
                wakings=body.get("wakings") or [],
            )
            one = await sleep_repo.summary(s, principal.user_id, None, entry_id)
            day = await sleep_repo.summary(s, principal.user_id, local_date)
            return status, one["entries"][0], day

        status, entry, day = await self.db.run(work, user_id=principal.user_id)
        return status == "created", {"entry": entry, "summary": day}

    async def update_entry(
        self, principal: Principal, entry_id: UUID, version: int, body: Mapping[str, Any]
    ) -> dict[str, Any]:
        await self._require(principal)

        async def work(s: DbSession) -> tuple[dict[str, Any], dict[str, Any]]:
            await sleep_repo.update_entry(
                s,
                principal.user_id,
                entry_id,
                version=version,
                sleep_start=body["sleep_start"],
                wake_time=body["wake_time"],
                wakings=body.get("wakings") or [],
            )
            one = await sleep_repo.summary(s, principal.user_id, None, entry_id)
            day = await sleep_repo.summary(s, principal.user_id, date.fromisoformat(one["date"]))
            return one["entries"][0], day

        try:
            entry, day = await self.db.run(work, user_id=principal.user_id)
        except AppError as exc:
            await self._enrich_conflict(principal, entry_id, exc)
            raise
        return {"entry": entry, "summary": day}

    async def delete_entry(self, principal: Principal, entry_id: UUID, version: int) -> None:
        await self._require(principal)
        try:
            await self.db.run(
                lambda s: sleep_repo.delete_entry(s, principal.user_id, entry_id, version),
                user_id=principal.user_id,
            )
        except AppError as exc:
            await self._enrich_conflict(principal, entry_id, exc)
            raise

    async def _enrich_conflict(self, principal: Principal, entry_id: UUID, exc: AppError) -> None:
        if exc.code is not ErrorCode.VERSION_CONFLICT:
            return
        one = await self.db.run(
            lambda s: sleep_repo.summary(s, principal.user_id, None, entry_id),
            user_id=principal.user_id,
            readonly=True,
        )
        if one["entries"]:
            exc.extra["current"] = one["entries"][0]

    async def set_goal(self, principal: Principal, goal_min: int) -> dict[str, int]:
        await self.db.run(
            lambda s: sleep_repo.set_goal(s, principal.user_id, goal_min),
            user_id=principal.user_id,
        )
        return {"goal_min": goal_min}
