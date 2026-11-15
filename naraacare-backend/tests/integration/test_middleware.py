"""The middleware stack end to end (doc 07 §5, SEC-3.x): headers, request id, limits, envelope."""

from __future__ import annotations

import json
import uuid
from typing import Annotated, Any

import pytest
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, ConfigDict

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.validators import SafeName, SafeSearchQuery, SafeText500
from app.middleware.rate_limit import rate_limit
from app.middleware.security_headers import SECURITY_HEADERS
from tests.conftest import AppFactory, AppHarness

router = APIRouter()


class EchoRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    name: SafeName
    note: SafeText500 | None = None


@router.post("/test/echo")
async def echo(body: EchoRequest) -> dict[str, Any]:
    return body.model_dump()


@router.get("/test/search")
async def search(q: Annotated[SafeSearchQuery, Query()]) -> dict[str, str]:
    return {"q": q}


@router.get("/test/boom")
async def boom() -> None:
    raise RuntimeError("secret detail: priya@example.com")


@router.get("/test/conflict")
async def conflict() -> None:
    raise AppError(ErrorCode.USERNAME_TAKEN)


@router.get("/test/limited", dependencies=[Depends(rate_limit("search"))])
async def limited() -> dict[str, bool]:
    return {"ok": True}


@pytest.fixture
def harness(app_factory: AppFactory) -> AppHarness:
    return app_factory(routers=[router])


def _assert_security_headers(headers: Any) -> None:
    for name, value in SECURITY_HEADERS.items():
        assert headers[name] == value, name
    assert headers["Cache-Control"] == "no-store"
    assert "server" not in {k.lower() for k in headers}


@pytest.mark.parametrize(
    ("method", "path", "body", "status"),
    [
        ("GET", "/api/v1/health/live", None, 200),
        ("POST", "/api/v1/test/echo", {"name": "<b>"}, 422),
        ("GET", "/api/v1/nope", None, 404),
        ("GET", "/api/v1/test/conflict", None, 409),
        ("GET", "/api/v1/test/boom", None, 500),
    ],
)
def test_security_headers_on_every_status(
    harness: AppHarness, method: str, path: str, body: Any, status: int
) -> None:
    response = harness.client.request(method, path, json=body)
    assert response.status_code == status
    _assert_security_headers(response.headers)


def test_request_id_generated_and_echoed(harness: AppHarness) -> None:
    response = harness.client.get("/api/v1/nope")
    request_id = response.headers["X-Request-ID"]
    assert uuid.UUID(request_id)
    assert response.json()["error"]["request_id"] == request_id


def test_client_request_id_kept_only_if_uuid(harness: AppHarness) -> None:
    given = str(uuid.uuid4())
    assert (
        harness.client.get("/api/v1/health/live", headers={"X-Request-ID": given}).headers[
            "X-Request-ID"
        ]
        == given
    )
    replaced = harness.client.get("/api/v1/health/live", headers={"X-Request-ID": "<script>"})
    assert replaced.headers["X-Request-ID"] != "<script>"
    assert uuid.UUID(replaced.headers["X-Request-ID"])


def test_500_reveals_nothing(harness: AppHarness, capsys: pytest.CaptureFixture[str]) -> None:
    response = harness.client.get("/api/v1/test/boom")
    assert response.status_code == 500
    error = response.json()["error"]
    assert set(error) == {"code", "message", "request_id"}
    assert error["code"] == "INTERNAL_ERROR"
    assert "priya" not in response.text and "Traceback" not in response.text
    logs = capsys.readouterr().out
    assert "unhandled_exception" in logs
    assert "priya@example.com" not in logs  # exception message never logged


def test_validation_error_lists_field_names_only(
    harness: AppHarness, capsys: pytest.CaptureFixture[str]
) -> None:
    payload = "<img src=x onerror=alert(1)>"
    response = harness.client.post("/api/v1/test/echo", json={"name": "Priya", "note": payload})
    assert response.status_code == 422
    error = response.json()["error"]
    assert error["code"] == "VALIDATION_FAILED"
    assert error["fields"] == ["note"]
    assert payload not in response.text
    assert "onerror" not in capsys.readouterr().out


def test_unsafe_input_queues_a_security_event_without_the_value(harness: AppHarness) -> None:
    harness.client.post("/api/v1/test/echo", json={"name": "<script>alert(1)</script>"})
    assert len(harness.events.events) == 1
    event = harness.events.events[0]
    assert event.event_type == "validation_rejected"
    assert event.field_name == "name"
    assert event.ip is None  # the TestClient peer "testclient" is not an IP address
    assert "script" not in json.dumps(event.details)


def test_format_errors_do_not_count_as_attacks(harness: AppHarness) -> None:
    response = harness.client.post("/api/v1/test/echo", json={"name": "Priya2"})
    assert response.status_code == 422
    assert harness.events.events == []


def test_query_parameters_validated_too(harness: AppHarness) -> None:
    assert harness.client.get("/api/v1/test/search", params={"q": "dal"}).json() == {"q": "dal"}
    response = harness.client.get("/api/v1/test/search", params={"q": "{{7*7}}"})
    assert response.status_code == 422
    assert response.json()["error"]["fields"] == ["q"]


def test_extra_fields_and_wrong_types_rejected(harness: AppHarness) -> None:
    assert (
        harness.client.post("/api/v1/test/echo", json={"name": "A", "admin": True}).status_code
        == 422
    )
    assert harness.client.post("/api/v1/test/echo", json={"name": 5}).status_code == 422


def test_malformed_json_is_bad_request(harness: AppHarness) -> None:
    response = harness.client.post(
        "/api/v1/test/echo", content=b"{not json", headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "BAD_REQUEST"


def test_body_over_1_mb_is_413(harness: AppHarness) -> None:
    big = b"{" + b" " * (1_048_576 + 1) + b"}"
    response = harness.client.post(
        "/api/v1/test/echo", content=big, headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_chunked_body_over_limit_is_413(harness: AppHarness) -> None:
    def chunks() -> Any:
        for _ in range(17):
            yield b" " * 65536

    response = harness.client.post(
        "/api/v1/test/echo", content=chunks(), headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 413


def test_route_rate_limit_returns_429_with_retry_after(harness: AppHarness) -> None:
    statuses = [harness.client.get("/api/v1/test/limited").status_code for _ in range(31)]
    assert statuses[:30] == [200] * 30
    assert statuses[30] == 429
    response = harness.client.get("/api/v1/test/limited")
    assert int(response.headers["Retry-After"]) >= 1
    assert response.json()["error"]["code"] == "RATE_LIMITED"
    _assert_security_headers(response.headers)


def test_penalty_box_tightens_the_global_limit(harness: AppHarness) -> None:
    for _ in range(10):
        harness.client.post("/api/v1/test/echo", json={"name": "<b>"})
    statuses = [harness.client.get("/api/v1/health/live").status_code for _ in range(11)]
    assert 429 in statuses
    assert statuses.index(429) <= 10


def test_readiness_reports_dependencies(harness: AppHarness) -> None:
    response = harness.client.get("/api/v1/health/ready")
    assert response.status_code == 503  # the harness database is unavailable
    assert response.json() == {
        "status": "unavailable",
        "checks": {"database": "fail"},
    }


def test_docs_need_basic_auth_when_configured(app_factory: AppFactory) -> None:
    harness = app_factory(API_DOCS_ENABLED="true", API_DOCS_BASIC_AUTH="docs:s3cret-dev")
    assert harness.client.get("/api/v1/docs").status_code == 401
    assert harness.client.get("/api/v1/docs", auth=("docs", "wrong")).status_code == 401
    assert (
        harness.client.get("/api/v1/docs/openapi.json", auth=("docs", "s3cret-dev")).status_code
        == 200
    )


def test_fastapi_param_default_form_bypasses_validation() -> None:
    """Pins the FastAPI behaviour behind the Semgrep rule no-param-default-validation-bypass:
    `q: SafeX = Query()` drops the Safe* validator, `Annotated[SafeX, Query()]` keeps it. If FastAPI
    changes this, the rule can be relaxed."""
    from fastapi import FastAPI  # noqa: PLC0415
    from fastapi.testclient import TestClient  # noqa: PLC0415

    app = FastAPI()

    @app.get("/default-form")
    async def default_form(q: SafeSearchQuery = Query()) -> dict[str, str]:  # noqa: B008  # nosemgrep
        return {"q": q}

    @app.get("/annotated-form")
    async def annotated_form(q: Annotated[SafeSearchQuery, Query()]) -> dict[str, str]:
        return {"q": q}

    client = TestClient(app)
    assert client.get("/default-form", params={"q": "{{7*7}}"}).status_code == 200
    assert client.get("/annotated-form", params={"q": "{{7*7}}"}).status_code == 422
