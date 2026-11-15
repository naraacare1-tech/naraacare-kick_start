"""Sleep (doc 04 section 2.6). STAR only; logic in ``app.domain.sleep.service``.

PUT and DELETE take the version the client last saw in ``If-Match``; a stale version answers 409
VERSION_CONFLICT with the server copy in ``error.current``. Creates are idempotent by
``client_entry_id`` (201 first, 200 on a replay).
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Header, Query, Response, status

from app.api.v1.deps import SleepServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.schemas.common import JsonUUID
from app.schemas.sleep import SleepEntryCreate, SleepEntryUpdate, SleepGoalIn

router = APIRouter(tags=["sleep"])
WRITES = [Depends(user_limit("writes"))]
IfMatch = Annotated[int, Header(alias="If-Match", ge=1, le=2_000_000_000)]


@router.get("/sleep/summary")
async def sleep_summary(
    principal: CurrentUser,
    sleep: SleepServiceDep,
    on: Annotated[date | None, Query(alias="date")] = None,
) -> dict[str, Any]:
    return await sleep.summary(principal, on)


@router.post("/sleep/entries", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_entry(
    body: SleepEntryCreate, principal: CurrentUser, sleep: SleepServiceDep, response: Response
) -> dict[str, Any]:
    created, result = await sleep.log_entry(principal, body.model_dump())
    if not created:  # replay of the same client_entry_id (offline sync)
        response.status_code = status.HTTP_200_OK
    return result


@router.put("/sleep/entries/{entry_id}", dependencies=WRITES)
async def update_entry(
    entry_id: JsonUUID,
    body: SleepEntryUpdate,
    version: IfMatch,
    principal: CurrentUser,
    sleep: SleepServiceDep,
) -> dict[str, Any]:
    return await sleep.update_entry(principal, entry_id, version, body.model_dump())


@router.delete(
    "/sleep/entries/{entry_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def delete_entry(
    entry_id: JsonUUID, version: IfMatch, principal: CurrentUser, sleep: SleepServiceDep
) -> Response:
    await sleep.delete_entry(principal, entry_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/me/sleep-goal", dependencies=WRITES)
async def set_sleep_goal(
    body: SleepGoalIn, principal: CurrentUser, sleep: SleepServiceDep
) -> dict[str, int]:
    return await sleep.set_goal(principal, body.goal_min)
