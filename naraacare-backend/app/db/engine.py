"""Async SQLAlchemy engines (asyncpg) for the primary and the optional read replica.

* PgBouncer runs in transaction mode, so server-side prepared statements cannot be reused across
  transactions: asyncpg's statement cache is off and every prepared statement gets a unique name
  (SQLAlchemy's documented PgBouncer setup).
* No session settings are sent at connect time (PgBouncer rejects unknown startup parameters).
  Timeouts are role settings in the database (app_rw: statement_timeout 5 s, idle-in-transaction
  10 s; naraacare-database roles/010_roles.sql).
* TLS: ``verify-full`` with the database provider's CA bundle outside dev (enforced by Settings).
"""

from __future__ import annotations

import ssl
from typing import Any
from uuid import uuid4

from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from app.core.config import Settings


def _ssl_arg(mode: str, root_cert: str | None) -> ssl.SSLContext | bool:
    if mode == "disable":
        return False
    context = ssl.create_default_context(cafile=root_cert)
    if mode in {"require", "verify-ca"}:
        context.check_hostname = False
    if mode == "require":
        context.verify_mode = ssl.CERT_NONE
    return context


def _connect_args(settings: Settings) -> dict[str, Any]:
    return {
        "statement_cache_size": 0,
        "prepared_statement_name_func": lambda: f"__asyncpg_{uuid4()}__",
        "ssl": _ssl_arg(settings.DATABASE_SSL_MODE, settings.DATABASE_SSL_ROOT_CERT),
        "server_settings": {"application_name": settings.APP_NAME},
    }


def create_engines(settings: Settings) -> tuple[AsyncEngine, AsyncEngine | None]:
    common: dict[str, Any] = {
        "pool_size": settings.DATABASE_POOL_SIZE,
        "max_overflow": settings.DATABASE_MAX_OVERFLOW,
        "pool_pre_ping": True,
        "pool_recycle": 1800,
        "connect_args": _connect_args(settings),
    }
    primary = create_async_engine(settings.DATABASE_URL.get_secret_value(), **common)
    replica = (
        create_async_engine(settings.DATABASE_REPLICA_URL.get_secret_value(), **common)
        if settings.DATABASE_REPLICA_URL is not None
        else None
    )
    return primary, replica
