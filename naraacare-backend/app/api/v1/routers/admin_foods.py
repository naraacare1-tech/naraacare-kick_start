"""Nutritionist food maintenance (doc 04 section 2.16, OQ-42). Role nutritionist/admin AND a client
address in STAFF_IP_ALLOWLIST; anything else answers 404. The database re-checks the role and the
audit trigger records every change with the actor."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, status

from app.api.v1.deps import NutritionServiceDep
from app.core.security.authz import Principal, require_staff, user_limit
from app.schemas.common import JsonUUID
from app.schemas.nutrition import AdminFoodIn

router = APIRouter(prefix="/admin/foods", tags=["staff"])
staff_only = require_staff("nutritionist", "admin")
Nutritionist = Annotated[Principal, Depends(staff_only)]
STAFF_WRITES = [Depends(user_limit("staff_writes"))]


@router.post("", dependencies=STAFF_WRITES, status_code=status.HTTP_201_CREATED)
async def create_food(
    body: AdminFoodIn, principal: Nutritionist, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    return await nutrition.admin_upsert_food(principal, None, body.model_dump())


@router.patch("/{food_id}", dependencies=STAFF_WRITES)
async def replace_food(
    food_id: JsonUUID, body: AdminFoodIn, principal: Nutritionist, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    """Sends the complete food (the procedure replaces every field)."""
    return await nutrition.admin_upsert_food(principal, food_id, body.model_dump())
