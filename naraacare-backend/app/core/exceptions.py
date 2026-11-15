"""AppError and the uniform error envelope (doc 04 §1.1, doc 07 SEC-3.5).

Every error leaves the API as ``{"error": {"code", "message", "fields"?, "request_id", ...}}``.
Validation errors list field NAMES only; the rejected value never appears in a response or log.
Unexpected exceptions become 500 INTERNAL_ERROR with the request id and nothing else.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable, Mapping
from http import HTTPStatus
from typing import Any

import structlog
from fastapi import FastAPI, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.error_catalogue import CATALOGUE, ErrorCode
from app.core.security.request_context import current_request_id
from app.core.security.validators import UNSAFE_INPUT

log = structlog.get_logger(__name__)

# Called with (field names, request) when input was rejected as unsafe; wired to the security-event
# writer in main.py. Kept as a hook so this module has no database dependency.
UnsafeInputHook = Callable[[list[str], Request], Awaitable[None]]


class AppError(Exception):
    """A catalogued API error. ``extra`` carries safe, typed details (e.g. retry_after_s, or the
    server copy of a resource as ``current`` on 409 VERSION_CONFLICT; never request input)."""

    def __init__(
        self,
        code: ErrorCode,
        *,
        fields: list[str] | None = None,
        extra: Mapping[str, object] | None = None,
        headers: Mapping[str, str] | None = None,
    ) -> None:
        super().__init__(code.value)
        self.code = code
        self.fields = fields
        self.extra = dict(extra or {})
        self.headers = dict(headers or {})


def error_response(
    code: ErrorCode,
    *,
    fields: list[str] | None = None,
    extra: Mapping[str, Any] | None = None,
    headers: Mapping[str, str] | None = None,
) -> JSONResponse:
    spec = CATALOGUE[code]
    body: dict[str, Any] = {"code": code.value, "message": spec.message}
    if fields:
        body["fields"] = fields
    body.update(jsonable_encoder(dict(extra or {})))
    body["request_id"] = current_request_id()
    return JSONResponse({"error": body}, status_code=spec.status, headers=dict(headers or {}))


def _field_name(loc: tuple[int | str, ...]) -> str:
    """('body', 'profile', 'full_name') -> 'profile.full_name'; list indexes are kept."""
    parts = (
        [str(p) for p in loc[1:]]
        if loc and loc[0] in {"body", "query", "path", "header"}
        else [str(p) for p in loc]
    )
    return ".".join(parts) or "body"


def install_exception_handlers(
    app: FastAPI, on_unsafe_input: UnsafeInputHook | None = None
) -> None:
    async def handle_app_error(request: Request, exc: Exception) -> JSONResponse:
        if not isinstance(exc, AppError):  # registered for AppError only
            raise exc
        return error_response(exc.code, fields=exc.fields, extra=exc.extra, headers=exc.headers)

    async def handle_validation(request: Request, exc: Exception) -> JSONResponse:
        if not isinstance(
            exc, RequestValidationError
        ):  # registered for RequestValidationError only
            raise exc
        errors = exc.errors()
        fields = sorted({_field_name(tuple(e.get("loc", ()))) for e in errors})
        unsafe = sorted(
            {_field_name(tuple(e.get("loc", ()))) for e in errors if e.get("type") == UNSAFE_INPUT}
        )
        if any(e.get("type") == "json_invalid" for e in errors):
            return error_response(ErrorCode.BAD_REQUEST)
        log.info("validation_rejected", fields=fields, unsafe_fields=unsafe)
        if unsafe and on_unsafe_input is not None:
            await on_unsafe_input(unsafe, request)
        return error_response(ErrorCode.VALIDATION_FAILED, fields=fields)

    async def handle_http(request: Request, exc: Exception) -> JSONResponse:
        if not isinstance(
            exc, StarletteHTTPException
        ):  # registered for StarletteHTTPException only
            raise exc
        code = {
            401: ErrorCode.UNAUTHENTICATED,
            403: ErrorCode.FORBIDDEN,
            404: ErrorCode.NOT_FOUND,
            405: ErrorCode.METHOD_NOT_ALLOWED,
            413: ErrorCode.PAYLOAD_TOO_LARGE,
            415: ErrorCode.UNSUPPORTED_MEDIA_TYPE,
            429: ErrorCode.RATE_LIMITED,
        }.get(
            exc.status_code,
            ErrorCode.BAD_REQUEST
            if exc.status_code < HTTPStatus.INTERNAL_SERVER_ERROR
            else ErrorCode.INTERNAL_ERROR,
        )
        return error_response(code)

    async def handle_unexpected(request: Request, exc: Exception) -> JSONResponse:
        # exc_info goes through format_exc_info + redaction; the response carries nothing of it.
        log.error("unhandled_exception", exc_type=type(exc).__name__, exc_info=exc)
        return error_response(ErrorCode.INTERNAL_ERROR)

    app.add_exception_handler(AppError, handle_app_error)
    app.add_exception_handler(RequestValidationError, handle_validation)
    app.add_exception_handler(StarletteHTTPException, handle_http)
    app.add_exception_handler(Exception, handle_unexpected)
