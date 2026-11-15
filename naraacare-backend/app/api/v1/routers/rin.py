"""Rin AI (doc 04 section 2.10, STAR + ai_processing consent). Logic in
``app.domain.ai.rin_service``.

* ``POST /rin/conversations`` starts a chat; ``POST /rin/conversations/{id}/messages`` answers with
  ``text/event-stream``: ``start {conversation_id}``, ``delta {text}``, ``action {action_id, kind,
  payload}``, ``done {text, usage_pct, resets_at}`` or ``error {code, message}``. Gate failures
  (403 UPGRADE_REQUIRED / CONSENT_REQUIRED / DAILY_LIMIT_REACHED, 404, 503) come back as normal JSON
  errors before the stream starts.
* Proposed logs are only written by ``POST /rin/actions/{id}/accept``.
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query, Response, status
from fastapi.responses import StreamingResponse
from pydantic import AwareDatetime

from app.api.v1.deps import RinServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import SafeSearchQuery
from app.schemas.common import JsonUUID
from app.schemas.rin import RinActionAccept, RinPrompt

router = APIRouter(tags=["rin"])
WRITES = [Depends(user_limit("writes"))]
CHAT = [Depends(user_limit("rin_chat"))]
# No proxy buffering (the reply must arrive token by token); never cached.
SSE_HEADERS = {"Cache-Control": "no-store", "X-Accel-Buffering": "no"}


@router.get("/rin/usage")
async def usage(principal: CurrentUser, rin: RinServiceDep) -> dict[str, Any]:
    return await rin.usage(principal)


@router.get("/rin/conversations")
async def conversations(
    principal: CurrentUser,
    rin: RinServiceDep,
    q: Annotated[SafeSearchQuery | None, Query()] = None,
    before: Annotated[AwareDatetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 30,
) -> dict[str, Any]:
    return await rin.conversations(principal, query=q, before=before, limit=limit)


@router.post("/rin/conversations", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_conversation(principal: CurrentUser, rin: RinServiceDep) -> dict[str, Any]:
    return {"conversation_id": await rin.create_conversation(principal, None)}


@router.get("/rin/conversations/{conversation_id}/messages")
async def messages(
    conversation_id: JsonUUID,
    principal: CurrentUser,
    rin: RinServiceDep,
    before: Annotated[AwareDatetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> dict[str, Any]:
    return await rin.messages(principal, conversation_id, before=before, limit=limit)


@router.post("/rin/conversations/{conversation_id}/messages", dependencies=CHAT)
async def send(
    conversation_id: JsonUUID, body: RinPrompt, principal: CurrentUser, rin: RinServiceDep
) -> StreamingResponse:
    stream = await rin.start(principal, conversation_id, body.content, body.client_message_id)
    return StreamingResponse(stream, media_type="text/event-stream", headers=SSE_HEADERS)


@router.post("/rin/actions/{action_id}/accept", dependencies=WRITES)
async def accept_action(
    action_id: JsonUUID, body: RinActionAccept, principal: CurrentUser, rin: RinServiceDep
) -> dict[str, Any]:
    items = [i.model_dump() for i in body.items] if body.items is not None else None
    return await rin.accept_action(principal, action_id, items)


@router.post(
    "/rin/actions/{action_id}/dismiss", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def dismiss_action(
    action_id: JsonUUID, principal: CurrentUser, rin: RinServiceDep
) -> Response:
    await rin.dismiss_action(principal, action_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete(
    "/rin/conversations/{conversation_id}",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_conversation(
    conversation_id: JsonUUID, principal: CurrentUser, rin: RinServiceDep
) -> Response:
    await rin.delete_conversation(principal, conversation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/rin/memory", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def delete_memory(principal: CurrentUser, rin: RinServiceDep) -> Response:
    await rin.delete_memory(principal)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
