"""Devices, notification preferences and reminder schedules (doc 04 section 2.7). The notification
list itself arrives with the notification centre (Session 14)."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, Response, status

from app.api.v1.deps import NotificationServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.schemas.common import JsonUUID
from app.schemas.hydration import DeviceIn, NotificationPreferences, RemindersIn

router = APIRouter(tags=["notifications"])
WRITES = [Depends(user_limit("writes"))]


@router.post(
    "/devices", dependencies=[Depends(user_limit("devices"))], status_code=status.HTTP_201_CREATED
)
async def register_device(
    body: DeviceIn, principal: CurrentUser, notifications: NotificationServiceDep
) -> dict[str, Any]:
    return await notifications.register_device(principal, body.model_dump())


@router.delete(
    "/devices/{installation_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def revoke_device(
    installation_id: JsonUUID, principal: CurrentUser, notifications: NotificationServiceDep
) -> Response:
    await notifications.revoke_device(principal, installation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me/notification-preferences")
async def preferences(
    principal: CurrentUser, notifications: NotificationServiceDep
) -> dict[str, bool]:
    return await notifications.preferences(principal)


@router.put("/me/notification-preferences", dependencies=WRITES)
async def set_preferences(
    body: NotificationPreferences, principal: CurrentUser, notifications: NotificationServiceDep
) -> dict[str, bool]:
    return await notifications.set_preferences(principal, body.model_dump())


@router.get("/me/reminders")
async def reminders(
    principal: CurrentUser, notifications: NotificationServiceDep
) -> dict[str, Any]:
    return await notifications.reminders(principal)


@router.put("/me/reminders", dependencies=WRITES)
async def set_reminders(
    body: RemindersIn, principal: CurrentUser, notifications: NotificationServiceDep
) -> dict[str, Any]:
    return await notifications.set_reminders(principal, body.model_dump()["reminders"])
