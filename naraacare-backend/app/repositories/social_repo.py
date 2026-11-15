"""People, connections, blocks, Care Circles, chat and the in-app notification list (doc 04 sections
2.8 and 2.9). Stored routine calls only; membership, blocks, the 50-seat cap and the sharing rules
are enforced in the database (RLS + checks in each routine)."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

PEOPLE_SEARCH = db_call("SELECT * FROM social.fn_people_search(:user_id, :query)")
SUGGESTIONS = db_call("SELECT * FROM social.fn_suggestions(:user_id)")
CONNECTIONS = db_call("SELECT * FROM social.fn_connections(:user_id)")
BLOCKS = db_call("SELECT * FROM social.fn_blocks(:user_id)")
REQUEST_CONNECTION = db_call("CALL social.pr_request_connection(:user_id, :username, NULL, NULL)")
RESPOND_CONNECTION = db_call("CALL social.pr_respond_connection(:user_id, :connection_id, :accept)")
REMOVE_CONNECTION = db_call("CALL social.pr_remove_connection(:user_id, :connection_id)")
BLOCK = db_call("CALL social.pr_block(:user_id, :blocked_id)")
UNBLOCK = db_call("CALL social.pr_unblock(:user_id, :blocked_id)")

CIRCLES = db_call("SELECT * FROM social.fn_circles_for_user(:user_id)")
CIRCLE_DETAIL = db_call("SELECT * FROM social.fn_circle_detail(:user_id, :circle_id)")
CIRCLE_MEMBERS = db_call(
    "SELECT * FROM social.fn_circle_members(:user_id, :circle_id, :query, :after, :limit)"
)
MEMBER_AVATARS = db_call("SELECT * FROM social.fn_member_avatars(:user_id, :circle_id, :member_id)")
CIRCLE_FEED = db_call("SELECT * FROM social.fn_circle_feed(:user_id, :circle_id, :before, :limit)")
PENDING_INVITES = db_call("SELECT * FROM social.fn_pending_invites(:user_id)")
CREATE_CIRCLE = db_call(
    "CALL social.pr_create_circle(:user_id, :name, CAST(:invitee_ids AS uuid[]), "
    "CAST(:shared_avatars AS text[]), NULL, NULL)"
)
INVITE_MEMBERS = db_call(
    "CALL social.pr_invite_members(:user_id, :circle_id, CAST(:user_ids AS uuid[]), NULL)"
)
RESPOND_INVITE = db_call(
    "CALL social.pr_respond_invite(:user_id, :circle_id, :action, "
    "CAST(:shared_avatars AS text[]), NULL)"
)
UPDATE_SHARES = db_call(
    "CALL social.pr_update_shares(:user_id, :circle_id, CAST(:shared_avatars AS text[]))"
)
LEAVE_CIRCLE = db_call("CALL social.pr_leave_circle(:user_id, :circle_id)")
REMOVE_MEMBER = db_call("CALL social.pr_remove_member(:user_id, :circle_id, :member_id)")
SET_MEMBER_ROLE = db_call("CALL social.pr_set_member_role(:user_id, :circle_id, :member_id, :role)")
UPDATE_CIRCLE = db_call(
    "CALL social.pr_update_circle(:user_id, :circle_id, :name, :wallpaper_code)"
)
DELETE_CIRCLE = db_call("CALL social.pr_delete_circle(:user_id, :circle_id)")
SET_CIRCLE_PREFS = db_call(
    "CALL social.pr_set_circle_prefs(:user_id, :circle_id, :member_join_leave, :circle_updates, "
    ":goal_completions, :avatar_updates, :mentions, :new_messages)"
)
MARK_READ = db_call("CALL social.pr_mark_read(:user_id, :circle_id)")
CREATE_INVITE_LINK = db_call(
    "CALL social.pr_create_invite_link(:user_id, :circle_id, :token_hash, :max_uses, NULL, NULL)"
)
REVOKE_INVITE_LINK = db_call("CALL social.pr_revoke_invite_link(:user_id, :circle_id, :link_id)")
RESOLVE_INVITE_LINK = db_call(
    "CALL social.pr_resolve_invite_link(:user_id, :token_hash, NULL, NULL)"
)

MESSAGES = db_call("SELECT * FROM social.fn_messages(:user_id, :circle_id, :before, :limit)")
POST_MESSAGE = db_call(
    "CALL social.pr_post_message(:user_id, :circle_id, :client_message_id, :body, "
    "CAST(:mention_user_ids AS uuid[]), NULL, NULL, NULL)"
)
SHARE_AVATAR = db_call(
    "CALL social.pr_share_avatar(:user_id, :avatar_type, CAST(:circle_ids AS uuid[]), "
    "CAST(:user_ids AS uuid[]), NULL)"
)
DELETE_MESSAGE = db_call("CALL social.pr_delete_message(:user_id, :circle_id, :message_id)")

NOTIFICATIONS = db_call(
    "SELECT * FROM notify.fn_notifications(:user_id, :circle_id, :before, :limit)"
)
MARK_NOTIFICATIONS_READ = db_call(
    "CALL notify.pr_mark_notifications_read(:user_id, :circle_id, CAST(:ids AS uuid[]))"
)

_JSON_COLUMNS = frozenset(
    {"preferences", "members_preview", "last_message", "state", "summary", "params"}
)


def _row(row: Mapping[str, Any]) -> dict[str, Any]:
    """jsonb columns arrive as text from the driver; decode them."""
    return {
        k: json.loads(v) if k in _JSON_COLUMNS and isinstance(v, str | bytes) else v
        for k, v in row.items()
    }


def _rows(rows: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    return [_row(r) for r in rows]


# ------------------------------------------------------------------ people, connections, blocks
async def people_search(session: DbSession, user_id: UUID, query: str) -> list[dict[str, Any]]:
    return _rows(await session.fetch_all(PEOPLE_SEARCH, user_id=user_id, query=query))


async def suggestions(session: DbSession, user_id: UUID) -> list[dict[str, Any]]:
    return _rows(await session.fetch_all(SUGGESTIONS, user_id=user_id))


async def connections(session: DbSession, user_id: UUID) -> list[dict[str, Any]]:
    return _rows(await session.fetch_all(CONNECTIONS, user_id=user_id))


async def blocks(session: DbSession, user_id: UUID) -> list[dict[str, Any]]:
    return _rows(await session.fetch_all(BLOCKS, user_id=user_id))


async def request_connection(
    session: DbSession, user_id: UUID, username: str
) -> tuple[UUID | None, str]:
    row = await session.fetch_one(REQUEST_CONNECTION, user_id=user_id, username=username) or {}
    return row.get("o_connection_id"), str(row["o_status"])


async def respond_connection(
    session: DbSession, user_id: UUID, connection_id: UUID, *, accept: bool
) -> None:
    await session.execute(
        RESPOND_CONNECTION, user_id=user_id, connection_id=connection_id, accept=accept
    )


async def remove_connection(session: DbSession, user_id: UUID, connection_id: UUID) -> None:
    await session.execute(REMOVE_CONNECTION, user_id=user_id, connection_id=connection_id)


async def block(session: DbSession, user_id: UUID, blocked_id: UUID) -> None:
    await session.execute(BLOCK, user_id=user_id, blocked_id=blocked_id)


async def unblock(session: DbSession, user_id: UUID, blocked_id: UUID) -> None:
    await session.execute(UNBLOCK, user_id=user_id, blocked_id=blocked_id)


# ------------------------------------------------------------------ circles
async def circles(session: DbSession, user_id: UUID) -> list[dict[str, Any]]:
    return _rows(await session.fetch_all(CIRCLES, user_id=user_id))


async def circle_detail(session: DbSession, user_id: UUID, circle_id: UUID) -> dict[str, Any]:
    row = await session.fetch_one(CIRCLE_DETAIL, user_id=user_id, circle_id=circle_id)
    return _row(row or {})


async def circle_members(
    session: DbSession,
    user_id: UUID,
    circle_id: UUID,
    *,
    query: str | None = None,
    after: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    return _rows(
        await session.fetch_all(
            CIRCLE_MEMBERS,
            user_id=user_id,
            circle_id=circle_id,
            query=query,
            after=after,
            limit=limit,
        )
    )


async def member_avatars(
    session: DbSession, user_id: UUID, circle_id: UUID, member_id: UUID
) -> list[dict[str, Any]]:
    return _rows(
        await session.fetch_all(
            MEMBER_AVATARS, user_id=user_id, circle_id=circle_id, member_id=member_id
        )
    )


async def circle_feed(
    session: DbSession, user_id: UUID, circle_id: UUID, *, before: datetime | None, limit: int
) -> list[dict[str, Any]]:
    return _rows(
        await session.fetch_all(
            CIRCLE_FEED, user_id=user_id, circle_id=circle_id, before=before, limit=limit
        )
    )


async def pending_invites(session: DbSession, user_id: UUID) -> list[dict[str, Any]]:
    return _rows(await session.fetch_all(PENDING_INVITES, user_id=user_id))


async def create_circle(
    session: DbSession,
    user_id: UUID,
    *,
    name: str,
    invitee_ids: Sequence[UUID],
    shared_avatars: Sequence[str],
) -> tuple[UUID, int]:
    row = (
        await session.fetch_one(
            CREATE_CIRCLE,
            user_id=user_id,
            name=name,
            invitee_ids=list(invitee_ids),
            shared_avatars=list(shared_avatars),
        )
        or {}
    )
    return row["o_circle_id"], int(row["o_invited"])


async def invite_members(
    session: DbSession, user_id: UUID, circle_id: UUID, user_ids: Sequence[UUID]
) -> int:
    row = (
        await session.fetch_one(
            INVITE_MEMBERS, user_id=user_id, circle_id=circle_id, user_ids=list(user_ids)
        )
        or {}
    )
    return int(row["o_invited"])


async def respond_invite(
    session: DbSession,
    user_id: UUID,
    circle_id: UUID,
    *,
    action: str,
    shared_avatars: Sequence[str] | None = None,
) -> str:
    row = (
        await session.fetch_one(
            RESPOND_INVITE,
            user_id=user_id,
            circle_id=circle_id,
            action=action,
            shared_avatars=list(shared_avatars) if shared_avatars is not None else None,
        )
        or {}
    )
    return str(row["o_status"])


async def update_shares(
    session: DbSession, user_id: UUID, circle_id: UUID, shared_avatars: Sequence[str]
) -> None:
    await session.execute(
        UPDATE_SHARES, user_id=user_id, circle_id=circle_id, shared_avatars=list(shared_avatars)
    )


async def leave_circle(session: DbSession, user_id: UUID, circle_id: UUID) -> None:
    await session.execute(LEAVE_CIRCLE, user_id=user_id, circle_id=circle_id)


async def remove_member(
    session: DbSession, user_id: UUID, circle_id: UUID, member_id: UUID
) -> None:
    await session.execute(REMOVE_MEMBER, user_id=user_id, circle_id=circle_id, member_id=member_id)


async def set_member_role(
    session: DbSession, user_id: UUID, circle_id: UUID, member_id: UUID, role: str
) -> None:
    await session.execute(
        SET_MEMBER_ROLE, user_id=user_id, circle_id=circle_id, member_id=member_id, role=role
    )


async def update_circle(
    session: DbSession,
    user_id: UUID,
    circle_id: UUID,
    *,
    name: str | None,
    wallpaper_code: str | None,
) -> None:
    await session.execute(
        UPDATE_CIRCLE,
        user_id=user_id,
        circle_id=circle_id,
        name=name,
        wallpaper_code=wallpaper_code,
    )


async def delete_circle(session: DbSession, user_id: UUID, circle_id: UUID) -> None:
    await session.execute(DELETE_CIRCLE, user_id=user_id, circle_id=circle_id)


async def set_circle_prefs(
    session: DbSession, user_id: UUID, circle_id: UUID, prefs: Mapping[str, bool]
) -> None:
    await session.execute(SET_CIRCLE_PREFS, user_id=user_id, circle_id=circle_id, **prefs)


async def mark_read(session: DbSession, user_id: UUID, circle_id: UUID) -> None:
    await session.execute(MARK_READ, user_id=user_id, circle_id=circle_id)


async def create_invite_link(
    session: DbSession, user_id: UUID, circle_id: UUID, *, token_hash: bytes, max_uses: int | None
) -> tuple[UUID, datetime]:
    row = (
        await session.fetch_one(
            CREATE_INVITE_LINK,
            user_id=user_id,
            circle_id=circle_id,
            token_hash=token_hash,
            max_uses=max_uses,
        )
        or {}
    )
    return row["o_link_id"], row["o_expires_at"]


async def revoke_invite_link(
    session: DbSession, user_id: UUID, circle_id: UUID, link_id: UUID
) -> None:
    await session.execute(REVOKE_INVITE_LINK, user_id=user_id, circle_id=circle_id, link_id=link_id)


async def resolve_invite_link(
    session: DbSession, user_id: UUID, token_hash: bytes
) -> tuple[UUID, str]:
    row = await session.fetch_one(RESOLVE_INVITE_LINK, user_id=user_id, token_hash=token_hash) or {}
    return row["o_circle_id"], str(row["o_status"])


# ------------------------------------------------------------------ chat
async def messages(
    session: DbSession, user_id: UUID, circle_id: UUID, *, before: datetime | None, limit: int
) -> list[dict[str, Any]]:
    return _rows(
        await session.fetch_all(
            MESSAGES, user_id=user_id, circle_id=circle_id, before=before, limit=limit
        )
    )


async def post_message(
    session: DbSession,
    user_id: UUID,
    circle_id: UUID,
    *,
    client_message_id: UUID,
    body: str,
    mention_user_ids: Sequence[UUID],
) -> tuple[UUID, datetime, str]:
    row = (
        await session.fetch_one(
            POST_MESSAGE,
            user_id=user_id,
            circle_id=circle_id,
            client_message_id=client_message_id,
            body=body,
            mention_user_ids=list(mention_user_ids),
        )
        or {}
    )
    return row["o_message_id"], row["o_created_at"], str(row["o_status"])


async def share_avatar(
    session: DbSession,
    user_id: UUID,
    *,
    avatar_type: str,
    circle_ids: Sequence[UUID],
    user_ids: Sequence[UUID],
) -> int:
    row = (
        await session.fetch_one(
            SHARE_AVATAR,
            user_id=user_id,
            avatar_type=avatar_type,
            circle_ids=list(circle_ids),
            user_ids=list(user_ids),
        )
        or {}
    )
    return int(row.get("o_shared") or 0)


async def delete_message(
    session: DbSession, user_id: UUID, circle_id: UUID, message_id: UUID
) -> None:
    await session.execute(
        DELETE_MESSAGE, user_id=user_id, circle_id=circle_id, message_id=message_id
    )


# ------------------------------------------------------------------ notifications
async def notifications(
    session: DbSession,
    user_id: UUID,
    *,
    circle_id: UUID | None,
    before: datetime | None,
    limit: int,
) -> list[dict[str, Any]]:
    return _rows(
        await session.fetch_all(
            NOTIFICATIONS, user_id=user_id, circle_id=circle_id, before=before, limit=limit
        )
    )


async def mark_notifications_read(
    session: DbSession, user_id: UUID, *, circle_id: UUID | None, ids: Sequence[UUID] | None
) -> None:
    await session.execute(
        MARK_NOTIFICATIONS_READ,
        user_id=user_id,
        circle_id=circle_id,
        ids=list(ids) if ids is not None else None,
    )
