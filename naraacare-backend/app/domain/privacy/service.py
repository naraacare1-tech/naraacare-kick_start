"""Privacy centre, data export and account deletion for the API (doc 04 section 2.13, doc 07
SEC-7, Session 15).

* Export and deletion need a fresh proof of identity: the account password, or a 6-digit code
  sent to the account's own address (Google / Apple accounts have no password). See AuthService.
* Export: 1 per 24 h, idempotent by Idempotency-Key; the worker builds the ZIP and notifies the
  user. The file is served back by ``GET /privacy/exports/{id}/file`` to its owner only (no
  public URL).
* Deletion: 30-day grace (OQ-47). The database revokes every refresh token and push token; this
  layer also blocks the user's current access tokens and sends the "scheduled" email. The account
  stays usable for signing in again, so the user can cancel during the grace period.
"""

from __future__ import annotations

from collections.abc import Mapping
from typing import Any
from uuid import UUID

from fastapi import BackgroundTasks

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain.auth.service import AuthService
from app.integrations.email import send_quietly
from app.integrations.storage import ObjectStorage
from app.repositories import privacy_repo
from app.repositories.base import Database


def _public_export(row: Mapping[str, Any], download_prefix: str) -> dict[str, Any]:
    ready = row["status"] == "ready" and row["object_key"] is not None
    return {
        "export_id": row["export_id"],
        "status": row["status"],
        "requested_at": row["requested_at"],
        "ready_at": row["ready_at"],
        "expires_at": row["expires_at"] if ready else None,
        "size_bytes": row["size_bytes"] if ready else None,
        "download_url": f"{download_prefix}/privacy/exports/{row['export_id']}/file"
        if ready
        else None,
    }


class PrivacyService:
    def __init__(
        self, *, db: Database, auth: AuthService, storage: ObjectStorage, download_prefix: str
    ) -> None:
        self.db = db
        self.auth = auth
        self.storage = storage
        self.download_prefix = download_prefix

    async def status(self, principal: Principal) -> dict[str, Any]:
        return await self.db.run(
            lambda s: privacy_repo.status(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )

    async def start_reauth(self, principal: Principal, background: BackgroundTasks) -> UUID:
        return await self.auth.start_reauth(principal, background=background)

    async def request_export(
        self,
        principal: Principal,
        *,
        idempotency_key: UUID,
        proof: Mapping[str, Any],
        ip: str | None,
    ) -> tuple[dict[str, Any], bool]:
        await self.auth.verify_reauth(principal, ip=ip, **dict(proof))
        row = await self.db.run(
            lambda s: privacy_repo.request_export(s, principal.user_id, idempotency_key),
            user_id=principal.user_id,
        )
        return {"export_id": row["o_export_id"], "status": row["o_status"]}, bool(row["o_created"])

    async def export(self, principal: Principal, export_id: UUID) -> dict[str, Any]:
        row = await self.db.run(
            lambda s: privacy_repo.export(s, principal.user_id, export_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return _public_export(row, self.download_prefix)

    async def export_file(self, principal: Principal, export_id: UUID) -> bytes:
        row = await self.db.run(
            lambda s: privacy_repo.export(s, principal.user_id, export_id),
            user_id=principal.user_id,
            readonly=True,
        )
        if row["status"] != "ready" or row["object_key"] is None:
            raise AppError(ErrorCode.EXPORT_NOT_READY)
        data = await self.storage.get(str(row["object_key"]))
        if data is None:
            raise AppError(ErrorCode.NOT_FOUND)
        return data

    async def request_deletion(
        self,
        principal: Principal,
        *,
        proof: Mapping[str, Any],
        ip: str | None,
        background: BackgroundTasks,
    ) -> dict[str, Any]:
        await self.auth.verify_reauth(principal, ip=ip, **dict(proof))
        email = await self.auth.email_of(principal)
        row = await self.db.run(
            lambda s: privacy_repo.request_deletion(s, principal.user_id),
            user_id=principal.user_id,
        )
        await self.auth.revocations.revoke_user(principal.user_id)
        if row["o_created"]:
            background.add_task(send_quietly, self.auth.email, email, "deletion_scheduled", {})
        return {"scheduled_for": row["o_scheduled_for"]}

    async def cancel_deletion(self, principal: Principal) -> bool:
        return await self.db.run(
            lambda s: privacy_repo.cancel_deletion(s, principal.user_id),
            user_id=principal.user_id,
        )
