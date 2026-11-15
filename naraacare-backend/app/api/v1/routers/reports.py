"""Streak, PDF reports, Help & Support and sync (doc 04 sections 2.7, 2.11, 2.13, 2.14, Session 14).

* ``POST /reports`` is idempotent by ``Idempotency-Key`` (202 on create, 200 on a replay); the
  worker builds the PDF and notifies the user. ``GET /reports/{id}/file`` returns the PDF to its
  owner only.
* ``POST /support/tickets`` is the API's only multipart route (doc 04 section 1): ``category``,
  ``description`` and an optional ``screenshot``. The form fields are a Pydantic model, so they go
  through the same Safe* validators and error handling as JSON bodies; the file is checked and
  re-encoded by the support service (its name is validated, then dropped).
"""

from __future__ import annotations

from datetime import date
from typing import Annotated, Any

from fastapi import APIRouter, Depends, File, Form, Header, Query, Response, UploadFile, status
from pydantic import AwareDatetime, Field, TypeAdapter, ValidationError

from app.api.v1.deps import ReportServiceDep, SupportServiceDep, SyncServiceDep
from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import CurrentUser, user_limit
from app.core.security.validators import (
    SafeFileName,
    SafeOpaqueToken256,
    SafeSearchQuery,
    SafeYearMonth,
)
from app.domain.support.uploads import MAX_BYTES
from app.schemas.common import JsonUUID
from app.schemas.reports import FeatureRequestIn, ReportRequest, TicketForm

router = APIRouter(tags=["reports"])
WRITES = [Depends(user_limit("writes"))]
SUPPORT = [Depends(user_limit("support"))]
REPORTS = [Depends(user_limit("reports"))]

_FILE_NAME = TypeAdapter(SafeFileName)


# ------------------------------------------------------------------ streak
@router.get("/me/streak")
async def streak(
    principal: CurrentUser,
    reports: ReportServiceDep,
    month: Annotated[SafeYearMonth | None, Query()] = None,
) -> dict[str, Any]:
    return await reports.streak(principal, date.fromisoformat(f"{month}-01") if month else None)


# ------------------------------------------------------------------ reports
@router.post("/reports", dependencies=REPORTS, status_code=status.HTTP_202_ACCEPTED)
async def create_report(
    body: ReportRequest,
    principal: CurrentUser,
    reports: ReportServiceDep,
    response: Response,
    idempotency_key: Annotated[JsonUUID, Header(alias="Idempotency-Key")],
) -> dict[str, Any]:
    result, created = await reports.create(principal, idempotency_key, body.model_dump())
    if not created:
        response.status_code = status.HTTP_200_OK
    return result


@router.get("/reports")
async def list_reports(
    principal: CurrentUser,
    reports: ReportServiceDep,
    before: Annotated[AwareDatetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> dict[str, Any]:
    return await reports.list(principal, before=before, limit=limit)


@router.get("/reports/{report_id}")
async def get_report(
    report_id: JsonUUID, principal: CurrentUser, reports: ReportServiceDep
) -> dict[str, Any]:
    return await reports.get(principal, report_id)


@router.get("/reports/{report_id}/file")
async def report_file(
    report_id: JsonUUID, principal: CurrentUser, reports: ReportServiceDep
) -> Response:
    data, row = await reports.file(principal, report_id)
    name = f"naraacare-report-{row['period_from']:%Y%m%d}-{row['period_to']:%Y%m%d}.pdf"
    return Response(
        content=data,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{name}"',
            "Cache-Control": "no-store",
        },
    )


# ------------------------------------------------------------------ help & support
@router.get("/support/faqs")
async def faqs(
    principal: CurrentUser,
    support: SupportServiceDep,
    q: Annotated[SafeSearchQuery | None, Query()] = None,
) -> dict[str, Any]:
    return await support.faqs(principal, q)


@router.post("/support/tickets", dependencies=SUPPORT, status_code=status.HTTP_201_CREATED)
async def create_ticket(
    form: Annotated[TicketForm, Form()],
    principal: CurrentUser,
    support: SupportServiceDep,
    screenshot: Annotated[UploadFile | None, File()] = None,
) -> dict[str, Any]:
    data: bytes | None = None
    if screenshot is not None:
        try:
            if screenshot.filename:
                _FILE_NAME.validate_python(screenshot.filename)
        except ValidationError as exc:
            raise AppError(ErrorCode.UPLOAD_INVALID, fields=["screenshot"]) from exc
        data = await screenshot.read(MAX_BYTES + 1) or None
    return await support.create_ticket(
        principal, category=form.category, description=form.description, screenshot=data
    )


@router.post("/support/feature-requests", dependencies=SUPPORT, status_code=status.HTTP_201_CREATED)
async def create_feature_request(
    body: FeatureRequestIn, principal: CurrentUser, support: SupportServiceDep
) -> dict[str, Any]:
    return await support.create_feature_request(principal, title=body.title, benefit=body.benefit)


# ------------------------------------------------------------------ sync
@router.get("/sync/changes")
async def sync_changes(
    principal: CurrentUser,
    sync: SyncServiceDep,
    since: Annotated[SafeOpaqueToken256 | None, Query(), Field(min_length=8)] = None,
) -> dict[str, Any]:
    return await sync.changes(principal, since)
