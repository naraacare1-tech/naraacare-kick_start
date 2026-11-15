"""HTTP Basic auth in front of the interactive API docs on staging (doc 08: API_DOCS_BASIC_AUTH).

Docs are off in prod (Settings refuses otherwise). On staging they expose the full schema, so they
sit behind a shared credential; the comparison is constant-time.
"""

from __future__ import annotations

import base64
import binascii
import hmac

from starlette.responses import Response
from starlette.types import ASGIApp, Receive, Scope, Send


class DocsBasicAuthMiddleware:
    def __init__(self, app: ASGIApp, *, prefixes: tuple[str, ...], credential: str) -> None:
        self.app = app
        self.prefixes = prefixes
        self.expected = credential.encode()

    def _authorised(self, scope: Scope) -> bool:
        header = next((v for k, v in scope["headers"] if k == b"authorization"), b"")
        scheme, _, encoded = header.partition(b" ")
        if scheme.lower() != b"basic":
            return False
        try:
            supplied = base64.b64decode(encoded, validate=True)
        except (binascii.Error, ValueError):
            return False
        return hmac.compare_digest(supplied, self.expected)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if (
            scope["type"] == "http"
            and scope.get("path", "").startswith(self.prefixes)
            and not self._authorised(scope)
        ):
            response = Response(status_code=401, headers={"WWW-Authenticate": 'Basic realm="docs"'})
            await response(scope, receive, send)
            return
        await self.app(scope, receive, send)
