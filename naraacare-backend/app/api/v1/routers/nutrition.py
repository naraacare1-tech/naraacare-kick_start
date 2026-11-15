"""Daily nutrition summary and voice parsing (doc 04 section 2.4)."""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from app.api.v1.deps import NutritionServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.schemas.nutrition import VoiceParseRequest

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


@router.get("/daily-summary")
async def daily_summary(
    principal: CurrentUser,
    nutrition: NutritionServiceDep,
    on: Annotated[date | None, Query(alias="date")] = None,
) -> dict[str, Any]:
    """``date`` defaults to the user's local today."""
    return await nutrition.daily_summary(principal, on)


@router.post("/voice/parse", dependencies=[Depends(user_limit("voice_parse"))])
async def voice_parse(
    body: VoiceParseRequest, principal: CurrentUser, nutrition: NutritionServiceDep
) -> dict[str, Any]:
    """The transcript comes from on-device speech recognition; it is parsed, matched and returned
    for the user to confirm, never stored."""
    return await nutrition.voice_parse(principal, body.transcript)
