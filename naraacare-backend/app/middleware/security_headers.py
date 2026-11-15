"""Security headers on every response, including errors (doc 07 §5).

``Cache-Control: no-store`` everywhere except the public reference data, which the app may cache
(``GET /reference/*`` sets its own ``max-age`` + ETag). The ``Server`` header is removed so the
stack is not advertised.
"""

from __future__ import annotations

from starlette.datastructures import MutableHeaders
from starlette.types import ASGIApp, Message, Receive, Scope, Send

SECURITY_HEADERS: dict[str, str] = {
    "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    # Doc 07 wrote "()", which is not valid Permissions-Policy syntax; an API needs no browser
    # feature, so every powerful feature is disabled explicitly instead.
    "Permissions-Policy": (
        "accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), "
        "microphone=(), payment=(), usb=()"
    ),
}
CACHEABLE_PREFIXES: tuple[str, ...] = ("/api/v1/reference/",)
# Interactive docs (dev/staging only) need to load their own script and styles.
DOCS_PREFIXES: tuple[str, ...] = ("/api/v1/docs",)
DOCS_CSP = (
    "default-src 'none'; frame-ancestors 'none'; script-src 'self' https://cdn.jsdelivr.net "
    "'unsafe-inline'; style-src 'self' https://cdn.jsdelivr.net; img-src 'self' data: "
    "https://fastapi.tiangolo.com; connect-src 'self'"
)


class SecurityHeadersMiddleware:
    def __init__(self, app: ASGIApp) -> None:
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        path: str = scope.get("path", "")

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                headers = MutableHeaders(scope=message)
                for name, value in SECURITY_HEADERS.items():
                    headers[name] = value
                if path.startswith(DOCS_PREFIXES):
                    headers["Content-Security-Policy"] = DOCS_CSP
                if not path.startswith(CACHEABLE_PREFIXES) or "cache-control" not in headers:
                    headers["Cache-Control"] = "no-store"
                if "server" in headers:
                    del headers["server"]
            await send(message)

        await self.app(scope, receive, send_with_headers)
