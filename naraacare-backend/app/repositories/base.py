"""Database access: only calls to stored functions/procedures, one transaction per unit of work.

Rules (doc 07 SEC-4.1, doc 09 §4):
* Statements are module-level constants built with ``db_call()``, which accepts exactly
  ``SELECT * FROM schema.fn_name(:p, ...)``, ``SELECT schema.fn_name(...)`` or
  ``CALL schema.pr_name(:p, ..., NULL, ...)``. Anything else fails at import time, so no repository
  can run ad-hoc SQL, and values only ever travel as bound parameters.
* Every transaction first sets ``app.user_id`` and ``app.request_id`` with
  ``set_config(..., true)`` (transaction-local, safe under PgBouncer transaction pooling). The
  database functions assert the actor against ``app.user_id``.
* SQLSTATEs are mapped to catalogued errors (naraacare-database functions/README.md):
  22023/23xxx/22P02/22001 -> 422 (a few 22023 DETAIL codes keep their own code), 42501 -> 404,
  P0001 -> the app code in DETAIL,
  40001/40P01 -> retried once, then 503; 57014 (timeout) -> 503.
"""

from __future__ import annotations

from collections.abc import AsyncIterator, Awaitable, Callable, Mapping, Sequence
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Any
from uuid import UUID

import regex
import structlog
from sqlalchemy import TextClause, text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.ext.asyncio import AsyncConnection, AsyncEngine

from app.core.error_catalogue import DB_DETAIL_CODES, DB_VALIDATION_DETAIL_CODES, ErrorCode
from app.core.exceptions import AppError
from app.core.security.request_context import current_request_id

log = structlog.get_logger(__name__)

# A bound parameter, NULL, or a bound parameter cast to one of a few fixed types (no expressions).
_PARAM = r":[a-z][a-z0-9_]*|NULL|CAST\(:[a-z][a-z0-9_]* AS (?:inet|uuid\[\]|text\[\])\)"
_ARGS = rf"(?:(?:{_PARAM})(?:, (?:{_PARAM}))*)?"
# Validates call statements; this regex builds no SQL itself.
_CALL_SHAPE = regex.compile(
    rf"^(?:SELECT \* FROM [a-z]+\.fn_[a-z0-9_]+\({_ARGS}\)"  # noqa: S608  # nosec B608
    rf"|SELECT [a-z]+\.fn_[a-z0-9_]+\({_ARGS}\) AS [a-z_]+"
    rf"|CALL [a-z]+\.pr_[a-z0-9_]+\({_ARGS}\))$"
)
_SET_CONTEXT = text(
    "SELECT set_config('app.user_id', :user_id, true), "
    "set_config('app.request_id', :request_id, true)"
)
_VALIDATION_STATES = frozenset({"22023", "22P02", "22001", "23502", "23503", "23514"})
_RETRY_STATES = frozenset({"40001", "40P01"})
_UNAVAILABLE_STATES = frozenset({"57014", "55P03"})  # statement / lock timeout


class RetryableDbError(AppError):
    """Serialization failure or deadlock: the whole unit of work may be retried once."""

    def __init__(self) -> None:
        super().__init__(ErrorCode.SERVICE_UNAVAILABLE)


def db_call(statement: str) -> TextClause:
    """A stored function/procedure call as a reusable constant; rejects any other SQL."""
    if not _CALL_SHAPE.match(statement):
        raise ValueError(f"not a stored function/procedure call: {statement!r}")
    return text(statement)


@dataclass(frozen=True, slots=True)
class DbError:
    sqlstate: str | None
    detail: str | None


def _db_error(exc: DBAPIError) -> DbError:
    orig: Any = exc.orig
    cause: Any = getattr(orig, "__cause__", None)
    sqlstate = getattr(orig, "sqlstate", None) or getattr(cause, "sqlstate", None)
    detail = getattr(cause, "detail", None)
    return DbError(sqlstate=sqlstate, detail=detail)


def map_db_error(error: DbError) -> AppError | None:  # noqa: PLR0911 - one exit per mapping
    """The catalogued error for a database error, or None for unexpected ones (-> 500)."""
    state = error.sqlstate
    if state == "22023" and error.detail in DB_VALIDATION_DETAIL_CODES:
        return AppError(DB_VALIDATION_DETAIL_CODES[error.detail])
    if state in _VALIDATION_STATES:
        return AppError(ErrorCode.VALIDATION_FAILED)
    if state == "42501":
        return AppError(ErrorCode.NOT_FOUND)
    if state == "23505":
        return AppError(ErrorCode.ALREADY_EXISTS)
    if state == "P0001" and error.detail in DB_DETAIL_CODES:
        return AppError(DB_DETAIL_CODES[error.detail])
    if state in _RETRY_STATES:
        return RetryableDbError()
    if state in _UNAVAILABLE_STATES:
        return AppError(ErrorCode.SERVICE_UNAVAILABLE)
    return None


class DbSession:
    """One open transaction. Only ``db_call`` statements are accepted."""

    def __init__(self, conn: AsyncConnection) -> None:
        self._conn = conn

    async def set_actor(self, user_id: UUID) -> None:
        """Make ``user_id`` the actor for the rest of this transaction. Only for flows that
        authenticate inside the transaction (sign-up, OTP, sign-in, reset): the user has just been
        proven by a password, a code or a provider token."""
        await self._conn.execute(
            _SET_CONTEXT, {"user_id": str(user_id), "request_id": current_request_id() or ""}
        )

    async def execute(self, statement: TextClause, **params: object) -> None:
        """A procedure without INOUT parameters (no result row)."""
        await self._conn.execute(statement, params)

    async def fetch_one(self, statement: TextClause, **params: object) -> Mapping[str, Any] | None:
        result = await self._conn.execute(statement, params)
        if not result.returns_rows:
            return None
        row = result.mappings().first()
        return dict(row) if row is not None else None

    async def fetch_all(
        self, statement: TextClause, **params: object
    ) -> Sequence[Mapping[str, Any]]:
        result = await self._conn.execute(statement, params)
        return [dict(row) for row in result.mappings().all()]

    async def fetch_value(self, statement: TextClause, **params: object) -> Any:
        result = await self._conn.execute(statement, params)
        return result.scalar_one_or_none()


class Database:
    def __init__(self, primary: AsyncEngine, replica: AsyncEngine | None = None) -> None:
        self.primary = primary
        self.replica = replica

    @asynccontextmanager
    async def transaction(
        self, *, user_id: UUID | None = None, readonly: bool = False
    ) -> AsyncIterator[DbSession]:
        """``async with db.transaction(user_id=...) as s:`` commits on success, rolls back on error.
        Database errors leave as AppError (or propagate as 500 when unexpected)."""
        engine = self.replica if readonly and self.replica is not None else self.primary
        try:
            async with engine.begin() as conn:
                await conn.execute(
                    _SET_CONTEXT,
                    {
                        "user_id": str(user_id) if user_id else "",
                        "request_id": current_request_id() or "",
                    },
                )
                yield DbSession(conn)
        except DBAPIError as exc:
            error = _db_error(exc)
            mapped = map_db_error(error)
            log.warning(
                "db_error", sqlstate=error.sqlstate, error_code=mapped.code if mapped else None
            )
            if mapped is None:
                raise
            raise mapped from None

    async def run[T](
        self,
        work: Callable[[DbSession], Awaitable[T]],
        *,
        user_id: UUID | None = None,
        readonly: bool = False,
    ) -> T:
        """Run ``work`` in a transaction; a serialization failure or deadlock is retried once."""
        for attempt in (1, 2):
            try:
                async with self.transaction(user_id=user_id, readonly=readonly) as session:
                    return await work(session)
            except RetryableDbError:
                if attempt == 1:
                    log.info("db_retry")
                    continue
                raise
        raise AssertionError("unreachable")  # pragma: no cover

    async def dispose(self) -> None:
        await self.primary.dispose()
        if self.replica is not None:
            await self.replica.dispose()
