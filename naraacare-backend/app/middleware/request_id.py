"""Request id (doc 07 SEC-3.6): accept a client X-Request-ID only if it is a UUID, else make one.

The id is echoed in the response header and the error envelope, bound to every log line, and
copied into ``app.request_id`` for each DB transaction (audit rows carry it). A non-UUID header is
replaced, never logged: headers used as data follow the no-markup rule (doc 07 §4.4).
"""

from __future__ import annotations

import uuid

import structlog
from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.security.request_context import set_request_id, set_user_id

HEADER = "x-request-id"


def _valid_uuid(value: str) -> str | None:
    if len(value) != 36:  # noqa: PLR2004 - canonical UUID text form only
        return None
    try:
        return str(uuid.UUID(value))
    except ValueError:
        return None


class RequestIdMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        raw = next((v.decode("latin-1") for k, v in scope["headers"] if k == HEADER.encode()), "")
        request_id = _valid_uuid(raw) or str(uuid.uuid4())
        set_request_id(request_id)
        set_user_id(None)
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)

        async def send_with_id(message: Message) -> None:
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)[HEADER] = request_id
            await send(message)

        await self.app(scope, receive, send_with_id)
