"""Meals and saved meals (doc 04 section 2.4). Logic in ``app.domain.nutrition.service``.

PUT and DELETE take the version the client last saw in ``If-Match`` (optimistic concurrency); a
stale version answers 409 VERSION_CONFLICT with the server copy in ``error.current``.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Header, Query, Response, status

from app.api.v1.deps import NutritionServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.schemas.common import JsonUUID
from app.schemas.nutrition import MealCreate, MealUpdate, SavedMealCreate

router = APIRouter(tags=["nutrition"])
WRITES = [Depends(user_limit("writes"))]
IfMatch = Annotated[int, Header(alias="If-Match", ge=1, le=2_000_000_000)]


@router.post("/meals", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_meal(
    body: MealCreate,
    principal: CurrentUser,
    nutrition: NutritionServiceDep,
    response: Response,
    dry_run: Annotated[bool, Query()] = False,
) -> dict[str, Any]:
    """``dry_run=true`` (View Nutrition Summary): the same validation and server-side totals,
    nothing saved and not counted toward the daily limit (200)."""
    if dry_run:
        response.status_code = status.HTTP_200_OK
        return await nutrition.preview(principal, body.model_dump()["items"])
    created, result = await nutrition.log_meal(principal, body.model_dump())
    if not created:  # replay of the same client_entry_id (offline sync): nothing new was saved
        response.status_code = status.HTTP_200_OK
    return result


@router.put("/meals/{meal_id}", dependencies=WRITES)
async def update_meal(
    meal_id: JsonUUID,
    body: MealUpdate,
    version: IfMatch,
    principal: CurrentUser,
    nutrition: NutritionServiceDep,
) -> dict[str, Any]:
    return await nutrition.update_meal(principal, meal_id, version, body.model_dump())


@router.delete("/meals/{meal_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def delete_meal(
    meal_id: JsonUUID, version: IfMatch, principal: CurrentUser, nutrition: NutritionServiceDep
) -> Response:
    await nutrition.delete_meal(principal, meal_id, version)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/meals")
async def meals_on(
    on: Annotated[date, Query(alias="date")], principal: CurrentUser, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    return await nutrition.meals_on(principal, on)


@router.get("/meals/recent")
async def recent_meals(
    principal: CurrentUser,
    nutrition: NutritionServiceDep,
    limit: Annotated[int, Query(ge=1, le=10)] = 10,
) -> dict[str, Any]:
    return await nutrition.recent(principal, limit)


@router.get("/meals/{meal_id}/breakdown")
async def meal_breakdown(
    meal_id: JsonUUID, principal: CurrentUser, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    return await nutrition.breakdown(principal, meal_id)


@router.get("/saved-meals")
async def saved_meals(principal: CurrentUser, nutrition: NutritionServiceDep) -> dict[str, Any]:
    return await nutrition.saved_meals(principal)


@router.post("/saved-meals", dependencies=WRITES, status_code=status.HTTP_201_CREATED)
async def create_saved_meal(
    body: SavedMealCreate, principal: CurrentUser, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    data = body.model_dump()
    return await nutrition.save_meal(principal, data["name"], data["items"])


@router.delete(
    "/saved-meals/{saved_meal_id}", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT
)
async def delete_saved_meal(
    saved_meal_id: JsonUUID, principal: CurrentUser, nutrition: NutritionServiceDep
) -> Response:
    await nutrition.delete_saved_meal(principal, saved_meal_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
