"""Billing, store webhooks and referrals (doc 04 section 2.12). Logic in ``app.domain.billing`` and
``app.domain.referral``.

The two webhooks are the only unauthenticated write routes: they authenticate the caller themselves
(Pub/Sub OIDC token / Apple certificate chain) before anything is read or written, and answer 401
otherwise. No custom checkout exists (OQ-07): purchases happen in the stores only.
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Header, Query, Request, Response, status

from app.api.v1.deps import BillingServiceDep, ReferralServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import SafeOpaqueToken256
from app.schemas.billing import AppleNotification, PurchaseVerify, ReferralAttribute
from app.schemas.common import JsonUUID

router = APIRouter(tags=["billing"])
WRITES = [Depends(user_limit("writes"))]


@router.get("/billing/plans")
async def plans(principal: CurrentUser, billing: BillingServiceDep) -> dict[str, Any]:
    del principal  # signed-in users only; the plans are the same for everyone
    return await billing.plans()


@router.post("/billing/purchases/verify", dependencies=[Depends(user_limit("purchase_verify"))])
async def verify_purchase(
    body: PurchaseVerify,
    idempotency_key: Annotated[JsonUUID, Header(alias="Idempotency-Key")],
    principal: CurrentUser,
    billing: BillingServiceDep,
) -> dict[str, Any]:
    """Returns the user's entitlements after the store confirmed the purchase."""
    return await billing.verify(principal, body.model_dump(), idempotency_key)


@router.get("/billing/subscription")
async def subscription(principal: CurrentUser, billing: BillingServiceDep) -> dict[str, Any]:
    return await billing.subscription(principal)


@router.get("/billing/history")
async def history(
    principal: CurrentUser,
    billing: BillingServiceDep,
    cursor: Annotated[SafeOpaqueToken256 | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> dict[str, Any]:
    return await billing.history(principal, cursor, limit)


@router.post("/billing/webhooks/google", status_code=status.HTTP_204_NO_CONTENT)
async def google_webhook(request: Request, billing: BillingServiceDep) -> Response:
    """Pub/Sub push. The Authorization header is parsed by the OIDC verifier itself (strict
    ``Bearer <JWT>``), before the body is decoded."""
    await billing.webhook_google(request.headers.get("authorization"), await request.body())
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/billing/webhooks/apple")
async def apple_webhook(body: AppleNotification, billing: BillingServiceDep) -> Response:
    await billing.webhook_apple(body.signedPayload)
    return Response(status_code=status.HTTP_200_OK)


@router.get("/referrals/me")
async def referral_progress(
    principal: CurrentUser, referrals: ReferralServiceDep
) -> dict[str, Any]:
    return await referrals.me(principal)


@router.post("/referrals/attribute", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def attribute_referral(
    body: ReferralAttribute, principal: CurrentUser, referrals: ReferralServiceDep
) -> Response:
    await referrals.attribute(principal, body.code, body.installation_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
