"""Health probes. ``/health/live``: the process answers. ``/health/ready``: the database answers
too (load balancer target health). Readiness reports only ok/fail per dependency,
never error text."""

from __future__ import annotations

from typing import Literal

import structlog
from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from app.repositories.base import Database, db_call

router = APIRouter(tags=["health"])
log = structlog.get_logger(__name__)

PING = db_call("SELECT ops.fn_ping() AS ok")
Check = Literal["ok", "fail"]


class LiveResponse(BaseModel):
    status: Literal["ok"]


class ReadyChecks(BaseModel):
    database: Check


class ReadyResponse(BaseModel):
    status: Literal["ok", "unavailable"]
    checks: ReadyChecks


@router.get("/health/live")
async def live() -> LiveResponse:
    return LiveResponse(status="ok")


@router.get("/health/ready", responses={503: {"model": ReadyResponse}})
async def ready(request: Request) -> JSONResponse:
    db: Database = request.app.state.db
    database: Check = "fail"
    try:
        async with db.transaction() as session:
            database = "ok" if await session.fetch_value(PING) == 1 else "fail"
    except Exception as exc:  # any failure means not ready
        log.warning("readiness_database_failed", exc_type=type(exc).__name__)
    ok = database == "ok"
    body = ReadyResponse(
        status="ok" if ok else "unavailable", checks=ReadyChecks(database=database)
    )
    return JSONResponse(body.model_dump(), status_code=200 if ok else 503)
