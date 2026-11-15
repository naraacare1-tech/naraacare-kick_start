"""People, connections, Care Circles and chat (doc 04 sections 2.8 and 2.9, Session 12).

* The database decides: the username gate, blocks (hidden both ways), membership (non-members get
  42501 -> 404), admin rights, the 50-seat cap, "at least one share", sleep only between STAR users
  and admin succession on leave. This layer shapes requests and responses and drives realtime.
* Invite links: a random 256-bit token goes into the link once; only its SHA-256 is stored (a
  bearer secret, hashed like refresh tokens, so a database copy cannot be used to join circles).
* Realtime: after a write commits, the circle's active members (read in the same transaction) get a
  small event over the WebSocket hub. Events carry ids and the message the members may already read;
  push notifications are generic and never carry message text (OQ-41).
"""

from __future__ import annotations

import secrets
from collections.abc import Mapping, Sequence
from datetime import datetime
from hashlib import sha256
from typing import Any
from uuid import UUID

from app.core.security.authz import Principal
from app.domain.social.realtime import Hub, TicketStore
from app.repositories import social_repo
from app.repositories.base import Database, DbSession

INVITE_TOKEN_BYTES = 32
MEMBER_PAGE = 50  # a circle has at most 50 seats, so one page holds every member


def invite_token_hash(token: str) -> bytes:
    return sha256(token.encode("ascii")).digest()


async def _active_member_ids(s: DbSession, user_id: UUID, circle_id: UUID) -> list[UUID]:
    rows = await social_repo.circle_members(s, user_id, circle_id, limit=MEMBER_PAGE)
    return [r["user_id"] for r in rows if r["status"] == "active"]


class SocialService:
    def __init__(self, *, db: Database, hub: Hub, tickets: TicketStore, link_domain: str) -> None:
        self.db = db
        self.hub = hub
        self.tickets = tickets
        self.link_domain = link_domain

    # -------------------------------------------------------------- people and connections
    async def people_search(self, principal: Principal, query: str) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.people_search(s, principal.user_id, query),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def suggestions(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.suggestions(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def connections(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.connections(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def request_connection(self, principal: Principal, username: str) -> dict[str, Any]:
        connection_id, status = await self.db.run(
            lambda s: social_repo.request_connection(s, principal.user_id, username),
            user_id=principal.user_id,
        )
        return {"connection_id": connection_id, "status": status}

    async def respond_connection(
        self, principal: Principal, connection_id: UUID, *, accept: bool
    ) -> None:
        await self.db.run(
            lambda s: social_repo.respond_connection(
                s, principal.user_id, connection_id, accept=accept
            ),
            user_id=principal.user_id,
        )

    async def remove_connection(self, principal: Principal, connection_id: UUID) -> None:
        await self.db.run(
            lambda s: social_repo.remove_connection(s, principal.user_id, connection_id),
            user_id=principal.user_id,
        )

    async def blocks(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.blocks(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def block(self, principal: Principal, user_id: UUID) -> None:
        await self.db.run(
            lambda s: social_repo.block(s, principal.user_id, user_id), user_id=principal.user_id
        )

    async def unblock(self, principal: Principal, user_id: UUID) -> None:
        await self.db.run(
            lambda s: social_repo.unblock(s, principal.user_id, user_id), user_id=principal.user_id
        )

    # -------------------------------------------------------------- circles
    async def circles(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.circles(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def create_circle(self, principal: Principal, body: Mapping[str, Any]) -> dict[str, Any]:
        async def work(s: DbSession) -> dict[str, Any]:
            circle_id, invited = await social_repo.create_circle(
                s,
                principal.user_id,
                name=body["name"],
                invitee_ids=body["invitee_user_ids"],
                shared_avatars=body["shared_avatars"],
            )
            detail = await social_repo.circle_detail(s, principal.user_id, circle_id)
            return {**detail, "invited": invited}

        return await self.db.run(work, user_id=principal.user_id)

    async def circle_detail(self, principal: Principal, circle_id: UUID) -> dict[str, Any]:
        return await self.db.run(
            lambda s: social_repo.circle_detail(s, principal.user_id, circle_id),
            user_id=principal.user_id,
            readonly=True,
        )

    async def update_circle(
        self, principal: Principal, circle_id: UUID, body: Mapping[str, Any]
    ) -> dict[str, Any]:
        async def work(s: DbSession) -> tuple[dict[str, Any], list[UUID]]:
            await social_repo.update_circle(
                s,
                principal.user_id,
                circle_id,
                name=body.get("name"),
                wallpaper_code=body.get("wallpaper_code"),
            )
            detail = await social_repo.circle_detail(s, principal.user_id, circle_id)
            return detail, await _active_member_ids(s, principal.user_id, circle_id)

        detail, members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, members)
        return detail

    async def delete_circle(self, principal: Principal, circle_id: UUID) -> None:
        async def work(s: DbSession) -> list[UUID]:
            members = await _active_member_ids(s, principal.user_id, circle_id)
            await social_repo.delete_circle(s, principal.user_id, circle_id)
            return members

        members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, members)

    async def members(
        self,
        principal: Principal,
        circle_id: UUID,
        *,
        query: str | None,
        after: str | None,
        limit: int,
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.circle_members(
                s, principal.user_id, circle_id, query=query, after=after, limit=limit
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        next_after = rows[-1]["username"] if len(rows) == limit else None
        return {"items": rows, "next_after": next_after}

    async def invite_members(
        self, principal: Principal, circle_id: UUID, user_ids: Sequence[UUID]
    ) -> dict[str, int]:
        invited = await self.db.run(
            lambda s: social_repo.invite_members(s, principal.user_id, circle_id, user_ids),
            user_id=principal.user_id,
        )
        return {"invited": invited}

    async def remove_member(self, principal: Principal, circle_id: UUID, member_id: UUID) -> None:
        async def work(s: DbSession) -> list[UUID]:
            await social_repo.remove_member(s, principal.user_id, circle_id, member_id)
            return await _active_member_ids(s, principal.user_id, circle_id)

        members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, [*members, member_id])

    async def set_member_role(
        self, principal: Principal, circle_id: UUID, member_id: UUID, role: str
    ) -> None:
        async def work(s: DbSession) -> list[UUID]:
            await social_repo.set_member_role(s, principal.user_id, circle_id, member_id, role)
            return await _active_member_ids(s, principal.user_id, circle_id)

        members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, members)

    async def leave_circle(self, principal: Principal, circle_id: UUID) -> None:
        async def work(s: DbSession) -> list[UUID]:
            members = await _active_member_ids(s, principal.user_id, circle_id)
            await social_repo.leave_circle(s, principal.user_id, circle_id)
            return members

        members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, members)

    async def member_avatars(
        self, principal: Principal, circle_id: UUID, member_id: UUID
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.member_avatars(s, principal.user_id, circle_id, member_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def update_shares(
        self, principal: Principal, circle_id: UUID, shared_avatars: Sequence[str]
    ) -> dict[str, Any]:
        async def work(s: DbSession) -> tuple[dict[str, Any], list[UUID]]:
            await social_repo.update_shares(s, principal.user_id, circle_id, shared_avatars)
            detail = await social_repo.circle_detail(s, principal.user_id, circle_id)
            return detail, await _active_member_ids(s, principal.user_id, circle_id)

        detail, members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, members)
        return detail

    async def share_avatar(
        self,
        principal: Principal,
        *,
        avatar_type: str,
        circle_ids: Sequence[UUID],
        user_ids: Sequence[UUID],
    ) -> dict[str, int]:
        """Share today's avatar card with own circles (Recent Updates) and connections (in-app
        notification); the database checks membership and connections and builds the card."""

        async def work(s: DbSession) -> tuple[int, dict[UUID, list[UUID]]]:
            shared = await social_repo.share_avatar(
                s,
                principal.user_id,
                avatar_type=avatar_type,
                circle_ids=circle_ids,
                user_ids=user_ids,
            )
            members = {c: await _active_member_ids(s, principal.user_id, c) for c in circle_ids}
            return shared, members

        shared, members = await self.db.run(work, user_id=principal.user_id)
        if user_ids:
            await self.hub.publish(list(user_ids), {"type": "notification"})
        for circle_id, ids in members.items():
            await self._circle_changed(circle_id, ids)
        return {"shared": shared}

    async def feed(
        self, principal: Principal, circle_id: UUID, *, before: datetime | None, limit: int
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.circle_feed(
                s, principal.user_id, circle_id, before=before, limit=limit
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        next_before = rows[-1]["occurred_at"] if len(rows) == limit else None
        return {"items": rows, "next_before": next_before}

    async def set_circle_prefs(
        self, principal: Principal, circle_id: UUID, prefs: Mapping[str, bool]
    ) -> dict[str, bool]:
        await self.db.run(
            lambda s: social_repo.set_circle_prefs(s, principal.user_id, circle_id, prefs),
            user_id=principal.user_id,
        )
        return dict(prefs)

    # -------------------------------------------------------------- invites and invite links
    async def pending_invites(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.pending_invites(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"items": rows}

    async def respond_invite(
        self,
        principal: Principal,
        circle_id: UUID,
        action: str,
        shared_avatars: Sequence[str] | None = None,
    ) -> dict[str, Any] | None:
        """accept -> the circle (the caller is now a member); decline / later -> None."""

        async def work(s: DbSession) -> tuple[dict[str, Any] | None, list[UUID]]:
            await social_repo.respond_invite(
                s, principal.user_id, circle_id, action=action, shared_avatars=shared_avatars
            )
            if action != "accept":
                return None, []
            detail = await social_repo.circle_detail(s, principal.user_id, circle_id)
            return detail, await _active_member_ids(s, principal.user_id, circle_id)

        detail, members = await self.db.run(work, user_id=principal.user_id)
        await self._circle_changed(circle_id, members)
        return detail

    async def create_invite_link(
        self, principal: Principal, circle_id: UUID, max_uses: int | None
    ) -> dict[str, Any]:
        token = secrets.token_urlsafe(INVITE_TOKEN_BYTES)
        link_id, expires_at = await self.db.run(
            lambda s: social_repo.create_invite_link(
                s,
                principal.user_id,
                circle_id,
                token_hash=invite_token_hash(token),
                max_uses=max_uses,
            ),
            user_id=principal.user_id,
        )
        # The only time the token leaves the server; it is never logged or stored in plain text.
        return {
            "link_id": link_id,
            "url": f"https://{self.link_domain}/circle/{token}",
            "expires_at": expires_at,
        }

    async def revoke_invite_link(
        self, principal: Principal, circle_id: UUID, link_id: UUID
    ) -> None:
        await self.db.run(
            lambda s: social_repo.revoke_invite_link(s, principal.user_id, circle_id, link_id),
            user_id=principal.user_id,
        )

    async def resolve_invite_link(self, principal: Principal, token: str) -> dict[str, Any]:
        """The invite the link turned into (or the circle when already a member)."""

        async def work(s: DbSession) -> dict[str, Any]:
            circle_id, status = await social_repo.resolve_invite_link(
                s, principal.user_id, invite_token_hash(token)
            )
            if status == "member":
                detail = await social_repo.circle_detail(s, principal.user_id, circle_id)
                return {
                    "circle_id": circle_id,
                    "status": status,
                    "name": detail.get("name"),
                    "member_count": detail.get("member_count"),
                    "inviter_username": None,
                }
            invites = await social_repo.pending_invites(s, principal.user_id)
            invite = next(i for i in invites if i["circle_id"] == circle_id)
            return {
                "circle_id": circle_id,
                "status": status,
                "name": invite["name"],
                "member_count": invite["member_count"],
                "inviter_username": invite["inviter_username"],
            }

        return await self.db.run(work, user_id=principal.user_id)

    # -------------------------------------------------------------- chat
    async def messages(
        self, principal: Principal, circle_id: UUID, *, before: datetime | None, limit: int
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.messages(
                s, principal.user_id, circle_id, before=before, limit=limit
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        next_before = rows[-1]["created_at"] if len(rows) == limit else None
        return {"items": rows, "next_before": next_before}

    async def mark_read(self, principal: Principal, circle_id: UUID) -> None:
        await self.db.run(
            lambda s: social_repo.mark_read(s, principal.user_id, circle_id),
            user_id=principal.user_id,
        )

    async def post_message(
        self, principal: Principal, circle_id: UUID, body: Mapping[str, Any]
    ) -> tuple[bool, dict[str, Any]]:
        """(created, message). A replay of the same client_message_id returns created = False and
        sends nothing again."""

        async def work(s: DbSession) -> tuple[str, dict[str, Any], list[dict[str, Any]]]:
            message_id, created_at, status = await social_repo.post_message(
                s,
                principal.user_id,
                circle_id,
                client_message_id=body["client_message_id"],
                body=body["body"],
                mention_user_ids=body["mention_user_ids"],
            )
            members = await social_repo.circle_members(
                s, principal.user_id, circle_id, limit=MEMBER_PAGE
            )
            page = await social_repo.messages(
                s, principal.user_id, circle_id, before=None, limit=MEMBER_PAGE
            )
            stored = next((m for m in page if m["message_id"] == message_id), None)
            message = stored or {"message_id": message_id, "created_at": created_at}
            return status, message, members

        status, message, members = await self.db.run(work, user_id=principal.user_id)
        created = status == "created"
        if created:
            active = [m["user_id"] for m in members if m["status"] == "active"]
            await self.hub.publish(
                active, {"type": "message.created", "circle_id": circle_id, "message": message}
            )
            mentioned = set(body["mention_user_ids"]) & set(active)
            await self.hub.publish(mentioned, {"type": "notification", "circle_id": circle_id})
        return created, message

    async def delete_message(self, principal: Principal, circle_id: UUID, message_id: UUID) -> None:
        async def work(s: DbSession) -> list[UUID]:
            await social_repo.delete_message(s, principal.user_id, circle_id, message_id)
            return await _active_member_ids(s, principal.user_id, circle_id)

        members = await self.db.run(work, user_id=principal.user_id)
        await self.hub.publish(
            members, {"type": "message.deleted", "circle_id": circle_id, "message_id": message_id}
        )

    async def typing(self, user_id: UUID, circle_id: UUID) -> None:
        """Relay a typing indicator to the other active members; silently ignored for anyone
        who is not an active member (the database answers 42501)."""
        members = await self.db.run(
            lambda s: _active_member_ids(s, user_id, circle_id), user_id=user_id, readonly=True
        )
        others = [m for m in members if m != user_id]
        await self.hub.publish(
            others, {"type": "typing", "circle_id": circle_id, "user_id": user_id}
        )

    # -------------------------------------------------------------- notifications
    async def notifications(
        self,
        principal: Principal,
        *,
        circle_id: UUID | None,
        before: datetime | None,
        limit: int,
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: social_repo.notifications(
                s, principal.user_id, circle_id=circle_id, before=before, limit=limit
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        next_before = rows[-1]["created_at"] if len(rows) == limit else None
        return {"items": rows, "next_before": next_before}

    async def mark_notifications_read(
        self, principal: Principal, *, circle_id: UUID | None, ids: Sequence[UUID] | None
    ) -> None:
        await self.db.run(
            lambda s: social_repo.mark_notifications_read(
                s, principal.user_id, circle_id=circle_id, ids=ids
            ),
            user_id=principal.user_id,
        )

    async def _circle_changed(self, circle_id: UUID, user_ids: Sequence[UUID]) -> None:
        await self.hub.publish(user_ids, {"type": "circle.changed", "circle_id": circle_id})
