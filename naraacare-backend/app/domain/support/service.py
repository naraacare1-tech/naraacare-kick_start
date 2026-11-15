"""Help & Support (doc 04 section 2.13, OQ-51, Session 14).

* FAQs are static plain text (``faqs.py``); contact details come from settings, never from code.
  The phone line is a STAR benefit (Figma note), so it is only returned to STAR users.
* Report a problem: the optional screenshot is checked and re-encoded before anything is stored
  (``uploads.sanitize_screenshot``), saved under a random key, then the ticket row is written; if
  the row fails (limit, invalid text) the file is deleted again. Tickets and feature requests are
  emailed to the support inbox by the worker (``app.workers.jobs.support``), not in the request.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import structlog

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain.entitlements.service import EntitlementService
from app.domain.support import faqs
from app.domain.support.uploads import UploadRejectedError, sanitize_screenshot
from app.integrations.storage import ObjectStorage, new_key
from app.repositories import support_repo
from app.repositories.base import Database

log = structlog.get_logger(__name__)


@dataclass(frozen=True, slots=True)
class SupportContact:
    email: str
    phone: str | None
    phone_hours: str | None
    email_response: str | None


class SupportService:
    def __init__(
        self,
        *,
        db: Database,
        storage: ObjectStorage,
        entitlements: EntitlementService,
        contact: SupportContact,
    ) -> None:
        self.db = db
        self.storage = storage
        self.entitlements = entitlements
        self.contact = contact

    async def faqs(self, principal: Principal, query: str | None) -> dict[str, Any]:
        star = (await self.entitlements.get(principal.user_id)).tier == "star"
        return {
            "items": faqs.search(query),
            "contact": {
                "email": self.contact.email,
                "email_response": self.contact.email_response,
                "phone": self.contact.phone if star else None,
                "phone_hours": self.contact.phone_hours if star else None,
                "phone_requires_star": self.contact.phone is not None and not star,
            },
        }

    async def create_ticket(
        self, principal: Principal, *, category: str, description: str, screenshot: bytes | None
    ) -> dict[str, Any]:
        key: str | None = None
        if screenshot is not None:
            try:
                clean = sanitize_screenshot(screenshot)
            except UploadRejectedError as exc:
                log.info("support_upload_rejected", reason=exc.reason)
                raise AppError(ErrorCode.UPLOAD_INVALID, fields=["screenshot"]) from exc
            key = new_key("support", clean.extension)
            await self.storage.put(key, clean.data)
        try:
            row = await self.db.run(
                lambda s: support_repo.create_ticket(
                    s,
                    principal.user_id,
                    category=category,
                    description=description,
                    screenshot_key=key,
                ),
                user_id=principal.user_id,
            )
        except Exception:
            if key is not None:
                await self.storage.delete(key)
            raise
        return {"ticket_ref": row["o_ticket_ref"]}

    async def create_feature_request(
        self, principal: Principal, *, title: str, benefit: str
    ) -> dict[str, Any]:
        request_id = await self.db.run(
            lambda s: support_repo.create_feature_request(
                s, principal.user_id, title=title, benefit=benefit
            ),
            user_id=principal.user_id,
        )
        return {"request_id": request_id}
