"""One access-log line per request: method, route TEMPLATE, status, duration, user id, request id.

The route template (``/api/v1/meals/{meal_id}``) is logged instead of the path, and the query string
never, so ids, search terms and tokens in URLs stay out of the logs (doc 07 SEC-7.4). Run uvicorn
with ``--no-access-log``; this replaces its log, which prints full URLs.
"""

from __future__ import annotations

import time

import structlog
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.security.request_context import current_user_id

log = structlog.get_logger("access")


class AccessLogMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        start = time.perf_counter()
        status = 500

        async def capture(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, capture)
        finally:
            route = scope.get("route")
            user_id = current_user_id()
            log.info(
                "http_request",
                method=scope.get("method"),
                route=getattr(route, "path", "unmatched"),
                status=status,
                duration_ms=round((time.perf_counter() - start) * 1000, 1),
                user_id=str(user_id) if user_id else None,
            )
