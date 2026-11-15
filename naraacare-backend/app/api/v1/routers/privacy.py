"""Consents, privacy status, data export and account deletion (doc 04 section 2.13, doc 07 SEC-7).

* ``GET /privacy/status``: at launch: a scheduled deletion (offer Cancel), policies that need fresh
  consent (the app blocks until the user accepts them) and the latest export.
* ``POST /privacy/reauth``: emails a code for accounts without a password; export and deletion then
  send ``{challenge_id, code}`` instead of ``{password}``.
* ``POST /privacy/exports``: ``Idempotency-Key``; 202 on create, 200 on a replay; 1 per 24 h.
* ``POST /privacy/deletion-request``: 202 ``{scheduled_for}`` (30 days); all sessions end at once.
  ``DELETE /privacy/deletion-request``: cancel during the grace period (after signing in again).
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, BackgroundTasks, Depends, Header, Request, Response, status

from app.api.v1.deps import PrivacyServiceDep, ProfileServiceDep
from app.core.security.authz import CurrentUser, user_limit
from app.middleware.rate_limit import client_ip_or_none
from app.schemas.common import JsonUUID
from app.schemas.privacy import ConsentRequest, ConsentsResponse, ReauthProof

router = APIRouter(prefix="/privacy", tags=["privacy"])
SENSITIVE = [Depends(user_limit("privacy_sensitive"))]
WRITES = [Depends(user_limit("writes"))]


@router.get("/consents")
async def get_consents(principal: CurrentUser, profiles: ProfileServiceDep) -> ConsentsResponse:
    return ConsentsResponse.model_validate({"consents": await profiles.consents(principal)})


@router.post(
    "/consents",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(user_limit("consents"))],
)
async def post_consent(
    body: ConsentRequest, principal: CurrentUser, request: Request, profiles: ProfileServiceDep
) -> Response:
    await profiles.record_consent(principal, body.model_dump(), ip=client_ip_or_none(request.scope))
    return Response(status_code=status.HTTP_201_CREATED)


@router.get("/status")
async def privacy_status(principal: CurrentUser, privacy: PrivacyServiceDep) -> dict[str, Any]:
    return await privacy.status(principal)


@router.post("/reauth", dependencies=SENSITIVE, status_code=status.HTTP_202_ACCEPTED)
async def start_reauth(
    principal: CurrentUser, privacy: PrivacyServiceDep, background: BackgroundTasks
) -> dict[str, Any]:
    return {"challenge_id": await privacy.start_reauth(principal, background)}


@router.post("/exports", dependencies=SENSITIVE, status_code=status.HTTP_202_ACCEPTED)
async def request_export(  # noqa: PLR0917 - FastAPI injects each dependency by parameter
    body: ReauthProof,
    principal: CurrentUser,
    request: Request,
    response: Response,
    privacy: PrivacyServiceDep,
    idempotency_key: Annotated[JsonUUID, Header(alias="Idempotency-Key")],
) -> dict[str, Any]:
    result, created = await privacy.request_export(
        principal,
        idempotency_key=idempotency_key,
        proof=body.model_dump(),
        ip=client_ip_or_none(request.scope),
    )
    if not created:
        response.status_code = status.HTTP_200_OK
    return result


@router.get("/exports/{export_id}")
async def get_export(
    export_id: JsonUUID, principal: CurrentUser, privacy: PrivacyServiceDep
) -> dict[str, Any]:
    return await privacy.export(principal, export_id)


@router.get("/exports/{export_id}/file")
async def export_file(
    export_id: JsonUUID, principal: CurrentUser, privacy: PrivacyServiceDep
) -> Response:
    data = await privacy.export_file(principal, export_id)
    return Response(
        content=data,
        media_type="application/zip",
        headers={
            "Content-Disposition": 'attachment; filename="naraacare-data-export.zip"',
            "Cache-Control": "no-store",
        },
    )


@router.post("/deletion-request", dependencies=SENSITIVE, status_code=status.HTTP_202_ACCEPTED)
async def request_deletion(
    body: ReauthProof,
    principal: CurrentUser,
    request: Request,
    privacy: PrivacyServiceDep,
    background: BackgroundTasks,
) -> dict[str, Any]:
    return await privacy.request_deletion(
        principal,
        proof=body.model_dump(),
        ip=client_ip_or_none(request.scope),
        background=background,
    )


@router.delete("/deletion-request", dependencies=WRITES, status_code=status.HTTP_204_NO_CONTENT)
async def cancel_deletion(principal: CurrentUser, privacy: PrivacyServiceDep) -> Response:
    await privacy.cancel_deletion(principal)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
