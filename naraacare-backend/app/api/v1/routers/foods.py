"""Food search, food detail and barcode lookup (doc 04 section 2.4). Logic in
``app.domain.nutrition.service``."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Path, Query

from app.api.v1.deps import NutritionServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import SafeBarcode, SafeSearchQuery
from app.schemas.common import JsonUUID

router = APIRouter(prefix="/foods", tags=["nutrition"])


@router.get("/search", dependencies=[Depends(user_limit("search"))])
async def search_foods(
    q: Annotated[SafeSearchQuery, Query()],
    principal: CurrentUser,
    nutrition: NutritionServiceDep,
    limit: Annotated[int, Query(ge=1, le=25)] = 25,
) -> dict[str, Any]:
    return await nutrition.search(principal, q, limit)


@router.get("/barcode/{code}", dependencies=[Depends(user_limit("barcode"))])
async def barcode(
    code: Annotated[SafeBarcode, Path()], principal: CurrentUser, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    return await nutrition.barcode(principal, code)


@router.get("/{food_id}")
async def food_detail(
    food_id: JsonUUID, principal: CurrentUser, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    return await nutrition.food(principal, food_id)
