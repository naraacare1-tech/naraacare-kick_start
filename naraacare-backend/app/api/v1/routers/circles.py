"""Care Circles, invites, invite links and the in-app notification list (doc 04 sections 2.7 and
2.9). Membership and admin rights are checked in the database for every call: a non-member gets 404
for every circle resource. Logic in ``app.domain.social.service``."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query, Response, status
from pydantic import AwareDatetime

from app.api.v1.deps import SocialServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import SafeSearchQuery, SafeUsername
from app.schemas.common import JsonUUID
from app.schemas.social import (
    AvatarShareIn,
    CircleCreate,
    CircleNotificationSettings,
    CircleUpdate,
    InviteLinkCreate,
    InviteResolveIn,
    MemberRoleIn,
    MembersInviteIn,
    NotificationsReadIn,
    SharesIn,
)

router = APIRouter(tags=["circles"])
WRITES = [Depends(user_limit("writes"))]
Before = Annotated[AwareDatetime | None, Query()]


def _no_content() -> Response:
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/circles")
async def circles(principal: CurrentUser, social: SocialServiceDep) -> dict[str, Any]:
    return await social.circles(principal)


@router.post("/circles", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_circle(
    body: CircleCreate, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.create_circle(principal, body.model_dump())


@router.get("/circles/{circle_id}")
async def circle_detail(
    circle_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.circle_detail(principal, circle_id)


@router.patch("/circles/{circle_id}", dependencies=WRITES)
async def update_circle(
    circle_id: JsonUUID, body: CircleUpdate, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.update_circle(principal, circle_id, body.model_dump())


@router.delete("/circles/{circle_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def delete_circle(
    circle_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.delete_circle(principal, circle_id)
    return _no_content()


@router.get("/circles/{circle_id}/members")
async def members(
    circle_id: JsonUUID,
    principal: CurrentUser,
    social: SocialServiceDep,
    *,
    q: Annotated[SafeSearchQuery | None, Query()] = None,
    after: Annotated[SafeUsername | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 50,
) -> dict[str, Any]:
    return await social.members(principal, circle_id, query=q, after=after, limit=limit)


@router.post(
    "/circles/{circle_id}/members", dependencies=WRITES, status_code=status.HTTP_201_CREATED
)
async def invite_members(
    circle_id: JsonUUID, body: MembersInviteIn, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, int]:
    return await social.invite_members(principal, circle_id, body.user_ids)


@router.delete(
    "/circles/{circle_id}/members/{member_id}",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def remove_member(
    circle_id: JsonUUID, member_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.remove_member(principal, circle_id, member_id)
    return _no_content()


@router.put(
    "/circles/{circle_id}/members/{member_id}/role",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def set_member_role(
    circle_id: JsonUUID,
    member_id: JsonUUID,
    body: MemberRoleIn,
    principal: CurrentUser,
    social: SocialServiceDep,
) -> Response:
    await social.set_member_role(principal, circle_id, member_id, body.role)
    return _no_content()


@router.get("/circles/{circle_id}/members/{member_id}/avatars")
async def member_avatars(
    circle_id: JsonUUID, member_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.member_avatars(principal, circle_id, member_id)


@router.post(
    "/circles/{circle_id}/leave", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def leave_circle(
    circle_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.leave_circle(principal, circle_id)
    return _no_content()


@router.put("/circles/{circle_id}/shares", dependencies=WRITES)
async def update_shares(
    circle_id: JsonUUID, body: SharesIn, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.update_shares(principal, circle_id, body.shared_avatars)


@router.get("/circles/{circle_id}/feed")
async def feed(
    circle_id: JsonUUID,
    principal: CurrentUser,
    social: SocialServiceDep,
    before: Before = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 30,
) -> dict[str, Any]:
    return await social.feed(principal, circle_id, before=before, limit=limit)


@router.post("/avatar-shares", dependencies=WRITES)
async def share_avatar(
    body: AvatarShareIn, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, int]:
    """Share today's avatar inside NaraaCare only: own circles and connections (V029)."""
    return await social.share_avatar(
        principal,
        avatar_type=body.avatar_type,
        circle_ids=body.circle_ids,
        user_ids=body.user_ids,
    )


@router.put("/circles/{circle_id}/notification-settings", dependencies=WRITES)
async def set_circle_prefs(
    circle_id: JsonUUID,
    body: CircleNotificationSettings,
    principal: CurrentUser,
    social: SocialServiceDep,
) -> dict[str, bool]:
    return await social.set_circle_prefs(principal, circle_id, body.model_dump())


# ------------------------------------------------------------------ invites
@router.get("/circle-invites")
async def pending_invites(principal: CurrentUser, social: SocialServiceDep) -> dict[str, Any]:
    return await social.pending_invites(principal)


@router.post("/circle-invites/{circle_id}/accept", dependencies=WRITES)
async def accept_invite(
    circle_id: JsonUUID, body: SharesIn, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.respond_invite(principal, circle_id, "accept", body.shared_avatars) or {}


@router.post(
    "/circle-invites/{circle_id}/decline",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def decline_invite(
    circle_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.respond_invite(principal, circle_id, "decline")
    return _no_content()


@router.post(
    "/circle-invites/{circle_id}/later", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def postpone_invite(
    circle_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.respond_invite(principal, circle_id, "later")
    return _no_content()


# ------------------------------------------------------------------ invite links
@router.post(
    "/circles/{circle_id}/invite-links", dependencies=WRITES, status_code=status.HTTP_201_CREATED
)
async def create_invite_link(
    circle_id: JsonUUID, body: InviteLinkCreate, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.create_invite_link(principal, circle_id, body.max_uses)


@router.delete(
    "/circles/{circle_id}/invite-links/{link_id}",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def revoke_invite_link(
    circle_id: JsonUUID, link_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.revoke_invite_link(principal, circle_id, link_id)
    return _no_content()


@router.post("/invite-links/resolve", dependencies=[Depends(user_limit("invite_resolve"))])
async def resolve_invite_link(
    body: InviteResolveIn, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.resolve_invite_link(principal, body.token)


# ------------------------------------------------------------------ notifications
@router.get("/notifications")
async def notifications(
    principal: CurrentUser,
    social: SocialServiceDep,
    circle_id: Annotated[JsonUUID | None, Query()] = None,
    before: Before = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 30,
) -> dict[str, Any]:
    return await social.notifications(principal, circle_id=circle_id, before=before, limit=limit)


@router.post("/notifications/read", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def mark_notifications_read(
    body: NotificationsReadIn, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.mark_notifications_read(principal, circle_id=body.circle_id, ids=body.ids)
    return _no_content()
