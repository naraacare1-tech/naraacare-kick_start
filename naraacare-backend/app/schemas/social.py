"""People, connections, blocks and Care Circles (doc 04 sections 2.8 and 2.9). Models forbid unknown
fields and never carry the caller's ``user_id`` (it comes from the token). Free text is limited to
the circle name (SafeShortText50); everything else is ids, codes and booleans. The database checks
again (membership, 50 seats, sharing rules, blocks)."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import AfterValidator, Field

from app.core.security.validators import (
    SafeCode40,
    SafeOpaqueToken64,
    SafeShortText50,
    SafeUsername,
)
from app.schemas.common import JsonUUID
from app.schemas.nutrition import _Model

AvatarType = Literal["hydration", "nutrition", "sleep"]


def _unique[T](values: list[T]) -> list[T]:
    if len(set(values)) != len(values):
        raise ValueError("values must not repeat")
    return values


SharedAvatars = Annotated[
    list[AvatarType], Field(min_length=1, max_length=3), AfterValidator(_unique)
]
UserIds = Annotated[list[JsonUUID], Field(max_length=49), AfterValidator(_unique)]


class ConnectionRequestIn(_Model):
    username: SafeUsername


class BlockIn(_Model):
    user_id: JsonUUID


class CircleCreate(_Model):
    name: SafeShortText50
    invitee_user_ids: Annotated[UserIds, Field(default_factory=list)]
    shared_avatars: SharedAvatars


class CircleUpdate(_Model):
    name: SafeShortText50 | None = None
    wallpaper_code: SafeCode40 | None = None


class MembersInviteIn(_Model):
    user_ids: Annotated[UserIds, Field(min_length=1)]


class MemberRoleIn(_Model):
    role: Literal["admin", "member"]


class SharesIn(_Model):
    shared_avatars: SharedAvatars


class AvatarShareIn(_Model):
    """Share today's avatar inside NaraaCare: own circles and/or connections (V029). Only the
    avatar and the recipients come from the app; the values are read by the database."""

    avatar_type: AvatarType
    circle_ids: Annotated[
        list[JsonUUID], Field(max_length=10, default_factory=list), AfterValidator(_unique)
    ]
    user_ids: Annotated[
        list[JsonUUID], Field(max_length=20, default_factory=list), AfterValidator(_unique)
    ]


class InviteLinkCreate(_Model):
    max_uses: Annotated[int, Field(ge=1, le=49)] | None = None


class InviteResolveIn(_Model):
    token: SafeOpaqueToken64


class CircleNotificationSettings(_Model):
    member_join_leave: bool
    circle_updates: bool
    goal_completions: bool
    avatar_updates: bool
    mentions: bool
    new_messages: bool


class NotificationsReadIn(_Model):
    circle_id: JsonUUID | None = None
    ids: Annotated[list[JsonUUID], Field(max_length=100)] | None = None
