"""Turns any unhandled exception into the uniform 500 envelope (doc 07 SEC-3.5).

Placed inside the request-id, access-log and security-header middleware, so a 500 still carries
the request id and every security header (Starlette's own server-error handler sits outside all
user middleware and would bypass them). The response contains INTERNAL_ERROR + request id only;
the log line has the exception type and frames, never its message (app.core.logging).
"""

from __future__ import annotations

import structlog
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import error_response

log = structlog.get_logger(__name__)


class ErrorShieldMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        started = False

        async def tracking_send(message: Message) -> None:
            nonlocal started
            if message["type"] == "http.response.start":
                started = True
            await send(message)

        try:
            await self.app(scope, receive, tracking_send)
        except Exception as exc:
            log.error("unhandled_exception", exc_type=type(exc).__name__, exc_info=exc)
            if started:  # headers already sent: nothing safe left to do but close
                raise
            response = error_response(ErrorCode.INTERNAL_ERROR)
            await response(scope, receive, send)
