"""Request body limit (doc 07 §5, API4): 1 MB by default, larger only on listed upload routes.

A declared Content-Length over the limit is refused before anything is read. Otherwise the body is
read here, counting bytes, and refused as soon as it passes the limit, so a chunked or lying
upload cannot get past it. The (small) buffered body is then replayed to the app. Reading inside
the app instead would not work: FastAPI turns any error raised while it reads into a 400.
"""

from __future__ import annotations

from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import error_response


class BodySizeLimitMiddleware:
    def __init__(
        self, app: ASGIApp, *, max_bytes: int, overrides: dict[str, int] | None = None
    ) -> None:
        self.app = app
        self.max_bytes = max_bytes
        self.overrides = overrides or {}

    def _limit(self, path: str) -> int:
        return next(
            (n for prefix, n in self.overrides.items() if path.startswith(prefix)), self.max_bytes
        )

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = self._limit(scope.get("path", ""))
        declared = next((v for k, v in scope["headers"] if k == b"content-length"), None)
        if declared is not None:
            try:
                too_large = int(declared) > limit
            except ValueError:
                too_large = True
            if too_large:
                await error_response(ErrorCode.PAYLOAD_TOO_LARGE)(scope, receive, send)
                return

        chunks: list[bytes] = []
        received = 0
        while True:
            message = await receive()
            if message["type"] != "http.request":  # client went away
                return
            chunk = message.get("body", b"")
            received += len(chunk)
            if received > limit:
                await error_response(ErrorCode.PAYLOAD_TOO_LARGE)(scope, receive, send)
                return
            chunks.append(chunk)
            if not message.get("more_body", False):
                break

        body = b"".join(chunks)
        replayed = False

        async def replay() -> Message:
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": body, "more_body": False}
            return await receive()  # after the body: wait for disconnect as usual

        await self.app(scope, replay, send)
