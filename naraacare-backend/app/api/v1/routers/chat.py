"""Circle chat and realtime (doc 04 section 2.9).

* REST: send, list (newest first, ``before`` cursor), delete own message (admins: any), mark read.
  Sends are idempotent by ``client_message_id`` (201 first, 200 on a replay) and limited to 30 a
  minute per user.
* ``POST /realtime/ticket`` -> a single-use ticket valid 30 s; ``GET /ws?ticket=...`` opens the
  WebSocket. Client frames: ``{"type": "ping"}`` and ``{"type": "typing", "circle_id"}`` only, at
  most 8 KB each and 20 per 10 s; anything else is ignored, abuse closes the socket. Server events:
  ``message.created``, ``message.deleted``, ``typing``, ``circle.changed``, ``notification``.
"""

from __future__ import annotations

import asyncio
import contextlib
import time
from typing import Annotated, Any
from uuid import UUID

import structlog
from fastapi import APIRouter, Depends, Query, Response, WebSocket, status
from pydantic import AwareDatetime, TypeAdapter, ValidationError
from starlette.websockets import WebSocketDisconnect

from app.api.v1.deps import SocialServiceDep
from app.core.exceptions import AppError
from app.core.security.authz import CurrentUser, user_limit
from app.domain.social.realtime import TICKET_TTL_S, Hub, TicketStore
from app.domain.social.service import SocialService
from app.schemas.chat import ClientFrame, MessageCreate, TypingFrame
from app.schemas.common import JsonUUID

log = structlog.get_logger(__name__)

router = APIRouter(tags=["chat"])
WRITES = [Depends(user_limit("writes"))]

MAX_FRAME_CHARS = 8 * 1024
MAX_TICKET_CHARS = 64
FRAME_BUDGET = 20  # frames per window
FRAME_WINDOW_S = 10.0
IDLE_TIMEOUT_S = 90.0  # the app pings every 30 s
TYPING_INTERVAL_S = 3.0  # one typing relay per circle per 3 s
CLOSE_UNAUTHORIZED = 4401
_frames: TypeAdapter[Any] = TypeAdapter(ClientFrame)


@router.get("/circles/{circle_id}/messages")
async def messages(
    circle_id: JsonUUID,
    principal: CurrentUser,
    social: SocialServiceDep,
    before: Annotated[AwareDatetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 50,
) -> dict[str, Any]:
    return await social.messages(principal, circle_id, before=before, limit=limit)


@router.post(
    "/circles/{circle_id}/messages",
    dependencies=[Depends(user_limit("chat"))],
    status_code=status.HTTP_201_CREATED,
)
async def post_message(
    circle_id: JsonUUID,
    body: MessageCreate,
    principal: CurrentUser,
    social: SocialServiceDep,
    response: Response,
) -> dict[str, Any]:
    created, message = await social.post_message(principal, circle_id, body.model_dump())
    if not created:  # replay of the same client_message_id (retry after a lost response)
        response.status_code = status.HTTP_200_OK
    return message


@router.delete(
    "/circles/{circle_id}/messages/{message_id}",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def delete_message(
    circle_id: JsonUUID, message_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.delete_message(principal, circle_id, message_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post(
    "/circles/{circle_id}/messages/read",
    dependencies=WRITES,
    status_code=status.HTTP_204_NO_CONTENT,
)
async def mark_read(
    circle_id: JsonUUID, principal: CurrentUser, social: SocialServiceDep
) -> Response:
    await social.mark_read(principal, circle_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/realtime/ticket", dependencies=[Depends(user_limit("realtime_ticket"))])
async def realtime_ticket(principal: CurrentUser, social: SocialServiceDep) -> dict[str, Any]:
    tickets: TicketStore = social.tickets
    ticket = tickets.issue(principal.user_id, principal.session_id)
    return {"ticket": ticket, "expires_in_s": TICKET_TTL_S}


class _FrameBudget:
    def __init__(self) -> None:
        self.window_start = time.monotonic()
        self.count = 0

    def spend(self) -> bool:
        now = time.monotonic()
        if now - self.window_start >= FRAME_WINDOW_S:
            self.window_start, self.count = now, 0
        self.count += 1
        return self.count <= FRAME_BUDGET


@router.websocket("/ws")
async def websocket(ws: WebSocket) -> None:
    social: SocialService = ws.app.state.social_service
    raw = ws.query_params.get("ticket") or ""
    ticket = social.tickets.redeem(raw) if 0 < len(raw) <= MAX_TICKET_CHARS else None
    if ticket is None:
        await ws.close(code=CLOSE_UNAUTHORIZED)  # refused during the handshake
        return
    user_id = ticket.user_id
    await ws.accept()
    hub: Hub = social.hub
    await hub.add(user_id, ws, ticket.session_id)
    try:
        await _serve(ws, social, user_id)
    except WebSocketDisconnect:
        pass
    finally:
        hub.remove(user_id, ws)


async def _serve(ws: WebSocket, social: SocialService, user_id: UUID) -> None:
    budget = _FrameBudget()
    last_typing: dict[UUID, float] = {}
    while True:
        try:
            message = await asyncio.wait_for(ws.receive(), timeout=IDLE_TIMEOUT_S)
        except TimeoutError:
            await ws.close(code=status.WS_1000_NORMAL_CLOSURE)
            return
        if message["type"] == "websocket.disconnect":
            return
        text = message.get("text")
        if text is None:
            await ws.close(code=status.WS_1003_UNSUPPORTED_DATA)
            return
        if len(text) > MAX_FRAME_CHARS:
            await ws.close(code=status.WS_1009_MESSAGE_TOO_BIG)
            return
        if not budget.spend():
            log.info("ws_frame_budget_exceeded")
            await ws.close(code=status.WS_1008_POLICY_VIOLATION)
            return
        try:
            frame = _frames.validate_json(text)
        except ValidationError:
            continue  # unknown or malformed frames are ignored; their content is never echoed
        if isinstance(frame, TypingFrame):
            now = time.monotonic()
            if now - last_typing.get(frame.circle_id, 0.0) >= TYPING_INTERVAL_S:
                last_typing[frame.circle_id] = now
                # Not a member (404) or a passing database error: nothing to relay.
                with contextlib.suppress(AppError):
                    await social.typing(user_id, frame.circle_id)
        else:
            await ws.send_json({"type": "pong"})
