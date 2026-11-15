"""Referral programme (doc 04 section 2.12, doc 06 section 6, OQ-39, Session 11).

* ``GET /referrals/me`` creates the caller's code on first use and returns the link and progress.
* ``POST /referrals/attribute`` always answers 204: whether the code was unknown, the caller's own,
  the account older than 7 days, already attributed or the device already seen on another account
  is decided in the database and only logged (as a code), so the endpoint cannot be used to probe
  codes or accounts. The installation id is stored only as a blind index.
* Qualification (30 active days within 60) and rewards run in the nightly worker job.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

import structlog

from app.core.security.authz import Principal
from app.repositories import billing_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)


class ReferralService:
    def __init__(self, *, db: Database, link_domain: str) -> None:
        self.db = db
        self.link_domain = link_domain

    def link(self, code: str) -> str:
        return f"https://{self.link_domain}/invite/{code}"

    async def me(self, principal: Principal) -> dict[str, Any]:
        async def work(s: DbSession) -> dict[str, Any]:
            await billing_repo.ensure_code(s, principal.user_id)
            return await billing_repo.progress(s, principal.user_id)

        progress = await self.db.run(work, user_id=principal.user_id)
        return {**progress, "link": self.link(str(progress["code"]))}

    async def attribute(self, principal: Principal, code: str, installation_id: UUID) -> None:
        status = await self.db.run(
            lambda s: billing_repo.attribute(s, principal.user_id, code.upper(), installation_id),
            user_id=principal.user_id,
        )
        log.info("referral_attribution", outcome=status)
