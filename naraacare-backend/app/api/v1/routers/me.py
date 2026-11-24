"""The signed-in user's profile, onboarding, settings, targets and plan (doc 04 section 2.2).

There is no user id anywhere in these paths or bodies: the user is the token's subject.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Annotated

from fastapi import APIRouter, Depends, Path, Query, Request, Response, status

from app.api.v1.deps import EntitlementsDep, ProfileServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import SafeUsername
from app.middleware.rate_limit import client_ip_or_none
from app.schemas.me import (
    CompleteOnboardingRequest,
    EntitlementsResponse,
    GoalOptionsResponse,
    MeResponse,
    OnboardingResponse,
    OnboardingStepRequest,
    PreviewResponse,
    ProfilePatchRequest,
    ProfilePatchResponse,
    SettingsRequest,
    StepResponse,
    TargetsResponse,
    UsernameAvailability,
    UsernameRequest,
)

router = APIRouter(tags=["me"])
WRITES = [Depends(user_limit("writes"))]


@router.get("/me")
async def get_me(principal: CurrentUser, profiles: ProfileServiceDep) -> MeResponse:
    decrypted, entitlement = await profiles.load(principal)
    # Moves an existing user onto the current formulas once (calc_version change, 2026-11-24).
    await profiles.refresh_outdated_targets(principal, decrypted)
    return MeResponse.model_validate(profiles.me(decrypted, entitlement))


@router.patch("/me/profile", dependencies=WRITES)
async def patch_profile(
    body: ProfilePatchRequest, principal: CurrentUser, profiles: ProfileServiceDep
) -> ProfilePatchResponse:
    result = await profiles.update_profile(principal, body.model_dump(exclude_unset=True))
    return ProfilePatchResponse.model_validate(result)


@router.put("/me/settings", status_code=status.HTTP_204_NO_CONTENT, dependencies=WRITES)
async def put_settings(
    body: SettingsRequest, principal: CurrentUser, profiles: ProfileServiceDep
) -> Response:
    await profiles.update_settings(principal, body.model_dump())
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me/onboarding")
async def get_onboarding(principal: CurrentUser, profiles: ProfileServiceDep) -> OnboardingResponse:
    return OnboardingResponse.model_validate(await profiles.onboarding(principal))


@router.put("/me/onboarding/steps/{step}", dependencies=WRITES)
async def put_onboarding_step(
    step: Annotated[int, Path(ge=1, le=6)],
    body: OnboardingStepRequest,
    principal: CurrentUser,
    profiles: ProfileServiceDep,
) -> StepResponse:
    current = await profiles.save_step(principal, step, body.model_dump(exclude_unset=True))
    return StepResponse(current_step=current)


@router.post("/calculations/preview", dependencies=WRITES)
async def calculations_preview(
    principal: CurrentUser, profiles: ProfileServiceDep
) -> PreviewResponse:
    return PreviewResponse.model_validate(await profiles.preview(principal))


@router.post("/me/onboarding/complete", status_code=status.HTTP_201_CREATED, dependencies=WRITES)
async def complete_onboarding(
    body: CompleteOnboardingRequest,
    principal: CurrentUser,
    request: Request,
    profiles: ProfileServiceDep,
) -> TargetsResponse:
    targets = await profiles.complete(
        principal, [c.model_dump() for c in body.consents], ip=client_ip_or_none(request.scope)
    )
    return TargetsResponse.model_validate(targets)


@router.get("/me/goal-options")
async def goal_options(
    principal: CurrentUser,
    profiles: ProfileServiceDep,
    weight_kg: Annotated[Decimal | None, Query(ge=30, le=250)] = None,
    height_cm: Annotated[Decimal | None, Query(ge=120, le=230)] = None,
) -> GoalOptionsResponse:
    return GoalOptionsResponse.model_validate(
        await profiles.goal_options(principal, weight_kg, height_cm)
    )


@router.get("/me/targets/today")
async def targets_today(principal: CurrentUser, profiles: ProfileServiceDep) -> TargetsResponse:
    return TargetsResponse.model_validate(await profiles.targets_today(principal))


@router.get("/usernames/availability", dependencies=[Depends(user_limit("username_availability"))])
async def username_availability(
    username: Annotated[SafeUsername, Query()],
    principal: CurrentUser,
    profiles: ProfileServiceDep,
) -> UsernameAvailability:
    return UsernameAvailability(available=await profiles.username_available(principal, username))


@router.put("/me/username", status_code=status.HTTP_204_NO_CONTENT, dependencies=WRITES)
async def put_username(
    body: UsernameRequest, principal: CurrentUser, profiles: ProfileServiceDep
) -> Response:
    await profiles.set_username(principal, body.username)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me/entitlements")
async def get_entitlements(
    principal: CurrentUser, entitlements: EntitlementsDep
) -> EntitlementsResponse:
    entitlement = await entitlements.get(principal.user_id)
    return EntitlementsResponse.model_validate(
        {
            "tier": entitlement.tier,
            "source": entitlement.source,
            "expires_at": entitlement.expires_at,
            "features": entitlement.features,
            "limits": entitlement.limits,
        }
    )
