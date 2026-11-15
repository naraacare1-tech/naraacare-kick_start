"""Hydration and workouts (doc 04 section 2.5). Logic in ``app.domain.hydration.service``.

PUT and DELETE take the version the client last saw in ``If-Match``; a stale version answers 409
VERSION_CONFLICT with the server copy in ``error.current``. Creates are idempotent by
``client_entry_id`` (201 first, 200 on a replay).
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Header, Query, Response, status

from app.api.v1.deps import HydrationServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.schemas.common import JsonUUID
from app.schemas.hydration import (
    CustomDrinkEstimateIn,
    CustomDrinkIn,
    IntakeCreate,
    IntakeUpdate,
    TemperatureIn,
    WorkoutCreate,
)

router = APIRouter(tags=["hydration"])
WRITES = [Depends(user_limit("writes"))]
IfMatch = Annotated[int, Header(alias="If-Match", ge=1, le=2_000_000_000)]
OnDate = Annotated[date, Query(alias="date")]


@router.get("/hydration/status")
async def hydration_status(
    principal: CurrentUser,
    hydration: HydrationServiceDep,
    on: Annotated[date | None, Query(alias="date")] = None,
) -> dict[str, Any]:
    """Today by default; a past day (within 7 days) shows its end-of-day status."""
    return await hydration.status(principal, on)


@router.get("/hydration/drinks")
async def drinks(principal: CurrentUser, hydration: HydrationServiceDep) -> dict[str, Any]:
    return await hydration.drinks(principal)


@router.post("/hydration/intakes", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_intake(
    body: IntakeCreate, principal: CurrentUser, hydration: HydrationServiceDep, response: Response
) -> dict[str, Any]:
    created, result = await hydration.log_intake(principal, body.model_dump())
    if not created:  # replay of the same client_entry_id (offline sync)
        response.status_code = status.HTTP_200_OK
    return result


@router.get("/hydration/intakes")
async def intakes_on(
    on: OnDate, principal: CurrentUser, hydration: HydrationServiceDep
) -> dict[str, Any]:
    return await hydration.intakes_on(principal, on)


@router.put("/hydration/intakes/{intake_id}", dependencies=WRITES)
async def update_intake(
    intake_id: JsonUUID,
    body: IntakeUpdate,
    version: IfMatch,
    principal: CurrentUser,
    hydration: HydrationServiceDep,
) -> dict[str, Any]:
    return await hydration.update_intake(principal, intake_id, version, body.model_dump())


@router.delete(
    "/hydration/intakes/{intake_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def delete_intake(
    intake_id: JsonUUID, version: IfMatch, principal: CurrentUser, hydration: HydrationServiceDep
) -> Response:
    await hydration.delete_intake(principal, intake_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.put("/hydration/temperature", dependencies=WRITES)
async def set_temperature(
    body: TemperatureIn, principal: CurrentUser, hydration: HydrationServiceDep
) -> dict[str, Any]:
    return await hydration.set_temperature(principal, body.temperature_c)


@router.post(
    "/hydration/custom-drinks/estimate", dependencies=[Depends(user_limit("drink_estimate"))]
)
async def estimate_custom_drink(
    body: CustomDrinkEstimateIn, principal: CurrentUser, hydration: HydrationServiceDep
) -> dict[str, Any]:
    return await hydration.estimate_custom_drink(principal, body.name)


@router.post("/hydration/custom-drinks", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def save_custom_drink(
    body: CustomDrinkIn, principal: CurrentUser, hydration: HydrationServiceDep
) -> dict[str, Any]:
    return await hydration.save_custom_drink(principal, body.model_dump())


@router.post("/workouts", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_workout(
    body: WorkoutCreate, principal: CurrentUser, hydration: HydrationServiceDep, response: Response
) -> dict[str, Any]:
    created, result = await hydration.log_workout(principal, body.model_dump())
    if not created:
        response.status_code = status.HTTP_200_OK
    return result


@router.get("/workouts")
async def workouts_on(
    on: OnDate, principal: CurrentUser, hydration: HydrationServiceDep
) -> dict[str, Any]:
    return await hydration.workouts_on(principal, on)


@router.delete(
    "/workouts/{workout_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def delete_workout(
    workout_id: JsonUUID, version: IfMatch, principal: CurrentUser, hydration: HydrationServiceDep
) -> Response:
    await hydration.delete_workout(principal, workout_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
