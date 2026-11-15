"""People search, suggestions, connections and blocks (doc 04 section 2.8). Every route needs a
username (403 USERNAME_REQUIRED, enforced in the database); logic in ``app.domain.social.service``.
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query, Response, status

from app.api.v1.deps import SocialServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import SafeSearchQuery
from app.schemas.common import JsonUUID
from app.schemas.social import BlockIn, ConnectionRequestIn

router = APIRouter(tags=["people"])
WRITES = [Depends(user_limit("writes"))]


@router.get("/people/search", dependencies=[Depends(user_limit("people_search"))])
async def people_search(
    principal: CurrentUser, social: SocialServiceDep, q: Annotated[SafeSearchQuery, Query()]
) -> dict[str, Any]:
    return await social.people_search(principal, q)


@router.get("/people/suggestions")
async def suggestions(principal: CurrentUser, social: SocialServiceDep) -> dict[str, Any]:
    return await social.suggestions(principal)


@router.get("/connections")
async def connections(principal: CurrentUser, social: SocialServiceDep) -> dict[str, Any]:
    return await social.connections(principal)


@router.post("/connections/requests", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def request_connection(
    body: ConnectionRequestIn, principal: CurrentUser, social: SocialServiceDep
) -> dict[str, Any]:
    return await social.request_connection(principal, body.username)


@router.post(
    "/connections/requests/{connection_id}/accept",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def accept_connection(
    connection_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.respond_connection(principal, connection_id, accept=True)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/connections/requests/{connection_id}/decline",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def decline_connection(
    connection_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.respond_connection(principal, connection_id, accept=False)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "/connections/{connection_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def remove_connection(
    connection_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.remove_connection(principal, connection_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/blocks")
async def blocks(principal: CurrentUser, social: SocialServiceDep) -> dict[str, Any]:
    return await social.blocks(principal)


@router.post("/blocks", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def block(body: BlockIn, principal: CurrentUser, social: SocialServiceDep) -> Response:
    await social.block(principal, body.user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/blocks/{user_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def unblock(user_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep) -> Response:
    await social.unblock(principal, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
