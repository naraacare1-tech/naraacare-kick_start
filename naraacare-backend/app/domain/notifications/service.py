"""Devices, notification preferences and reminder schedules (doc 04 section 2.7, Session 09).

* The installation id and the FCM token are stored in plain text (owner decision, 2026-11-03).
* A device always belongs to the token subject; the body never names a user.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import Any
from uuid import UUID

from app.core.security.authz import Principal
from app.repositories import notify_repo
from app.repositories.base import Database


class NotificationService:
    def __init__(self, *, db: Database) -> None:
        self.db = db

    async def register_device(
        self, principal: Principal, body: Mapping[str, Any]
    ) -> dict[str, Any]:
        device_id = await self.db.run(
            lambda s: notify_repo.register_device(
                s,
                principal.user_id,
                installation_id=body["installation_id"],
                platform=body["platform"],
                push_token=body["push_token"],
                app_version=body["app_version"],
            ),
            user_id=principal.user_id,
        )
        return {"device_id": str(device_id), "platform": body["platform"]}

    async def revoke_device(self, principal: Principal, installation_id: UUID) -> None:
        await self.db.run(
            lambda s: notify_repo.revoke_device(s, principal.user_id, installation_id),
            user_id=principal.user_id,
        )

    async def preferences(self, principal: Principal) -> dict[str, bool]:
        return await self.db.run(
            lambda s: notify_repo.preferences(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )

    async def set_preferences(
        self, principal: Principal, values: Mapping[str, bool]
    ) -> dict[str, bool]:
        await self.db.run(
            lambda s: notify_repo.set_preferences(s, principal.user_id, values),
            user_id=principal.user_id,
        )
        return dict(values)

    async def reminders(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: notify_repo.reminders(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {
            "reminders": [
                {
                    "type": r["reminder_type"],
                    "enabled": bool(r["enabled"]),
                    "times": list(r["times"] or []),
                    "interval_min": r["interval_min"],
                    "saved": bool(r["saved"]),
                }
                for r in rows
            ]
        }

    async def set_reminders(
        self, principal: Principal, items: Sequence[Mapping[str, Any]]
    ) -> dict[str, Any]:
        payload = [
            {
                "type": i["type"],
                "enabled": i["enabled"],
                "times": [t.strftime("%H:%M") for t in i.get("times") or []],
                "interval_min": i.get("interval_min"),
            }
            for i in items
        ]
        await self.db.run(
            lambda s: notify_repo.set_reminders(s, principal.user_id, payload),
            user_id=principal.user_id,
        )
        return await self.reminders(principal)
