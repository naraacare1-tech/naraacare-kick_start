"""Per-request context (request id, authenticated user) via contextvars.

Set by middleware/dependencies and read by logging, the error envelope and the DB layer, which
copies them into ``app.request_id`` / ``app.user_id`` for every transaction.
"""

from __future__ import annotations

from contextvars import ContextVar
from uuid import UUID

_request_id: ContextVar[str | None] = ContextVar("request_id", default=None)
_user_id: ContextVar[UUID | None] = ContextVar("user_id", default=None)


def current_request_id() -> str | None:
    return _request_id.get()


def set_request_id(value: str | None) -> None:
    _request_id.set(value)


def current_user_id() -> UUID | None:
    return _user_id.get()


def set_user_id(value: UUID | None) -> None:
    _user_id.set(value)
