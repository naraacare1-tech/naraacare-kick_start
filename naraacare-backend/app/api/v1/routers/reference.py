"""Public reference data (doc 04 section 2.3). No user data; cacheable."""

from __future__ import annotations

from fastapi import APIRouter, Request, Response
from fastapi.responses import JSONResponse

from app.api.v1.deps import ReferenceDep
from app.repositories import reference_repo
from app.schemas.reference import PoliciesResponse

router = APIRouter(prefix="/reference", tags=["reference"])
CACHE_CONTROL = "public, max-age=3600"


@router.get("/bootstrap")
async def bootstrap(request: Request, reference: ReferenceDep) -> Response:
    data = await reference.bootstrap()
    etag = f'"{data.etag}"'
    headers = {"ETag": etag, "Cache-Control": CACHE_CONTROL}
    # Compared for equality only; the header value is never stored, logged or echoed.
    if request.headers.get("if-none-match") == etag:
        return Response(status_code=304, headers=headers)
    return JSONResponse(data.payload, headers=headers)


@router.get("/policies")
async def policies(request: Request) -> PoliciesResponse:
    rows = await request.app.state.db.run(reference_repo.policies, readonly=True)
    return PoliciesResponse.model_validate(
        {
            "policies": [
                {
                    "type": r["doc_type"],
                    "version": r["version"],
                    "url": r["url"],
                    "published_at": r["published_at"],
                }
                for r in rows
            ]
        }
    )
