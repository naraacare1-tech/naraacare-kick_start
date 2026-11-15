"""Mass assignment (Session 16, doc 07 API3 / SEC-4): no request can set a field it does not own.

* Every JSON or form body object in the API forbids unknown properties (``additionalProperties:
  false`` in OpenAPI, ``extra="forbid"`` in the models), including nested objects.
* Sending privileged fields (owner, role, tier, status, audit columns) alongside a valid body is
  refused with 422 on every route, before any handler runs. The user id only ever comes from the
  access token.
"""

from __future__ import annotations

import uuid
from typing import Any

import pytest

from app.api.v1.routers import admin_foods
from app.core.security.authz import Principal
from app.core.security.tokens import TokenService
from tests.conftest import AppFactory, AppHarness
from tests.integration.flows import NoLimits
from tests.security.payload_sweep import discover

PRIVILEGED = {
    "user_id": str(uuid.uuid4()),
    "owner_id": str(uuid.uuid4()),
    "role": "admin",
    "is_admin": True,
    "tier": "star",
    "tier_code": "star",
    "status": "active",
    "created_by": str(uuid.uuid4()),
    "deleted_at": None,
    "version": 1,
    "email_verified_at": "2026-01-01T00:00:00Z",
}


def open_objects(spec: dict[str, Any]) -> list[str]:
    """Paths of request-body object schemas that accept unknown properties."""
    found: list[str] = []
    schemas = spec.get("components", {}).get("schemas", {})

    def resolve(node: dict[str, Any]) -> dict[str, Any]:
        while "$ref" in node:
            node = schemas[node["$ref"].rsplit("/", 1)[-1]]
        return node

    def visit(node: dict[str, Any], where: str, seen: frozenset[str]) -> None:
        ref = node.get("$ref")
        if ref is not None:
            if ref in seen:
                return
            seen = seen | {ref}
        node = resolve(node)
        for key in ("anyOf", "oneOf", "allOf"):
            for i, option in enumerate(node.get(key, [])):
                visit(option, f"{where}|{key}{i}", seen)
        if node.get("type") == "object" or "properties" in node:
            if node.get("additionalProperties", True) is not False:
                found.append(where)
            for name, child in node.get("properties", {}).items():
                visit(child, f"{where}.{name}", seen)
        if node.get("type") == "array" and isinstance(node.get("items"), dict):
            visit(node["items"], f"{where}[]", seen)

    for path, ops in spec["paths"].items():
        for method, op in ops.items():
            for media, content in op.get("requestBody", {}).get("content", {}).items():
                visit(content["schema"], f"{method.upper()} {path} ({media})", frozenset())
    return found


@pytest.fixture
def harness(app_factory: AppFactory) -> AppHarness:
    return app_factory()


# The ticket form model lets exactly one extra key through, the ``screenshot`` file part (FastAPI
# puts files and fields in one form); any other field is refused (test_uploads.py).
OPEN_BY_DESIGN = {
    "POST /api/v1/support/tickets (multipart/form-data)",
    "POST /api/v1/support/tickets (multipart/form-data)|allOf0",
}


def test_every_request_body_object_forbids_unknown_fields(harness: AppHarness) -> None:
    assert sorted(set(open_objects(harness.app.openapi())) - OPEN_BY_DESIGN) == []


def test_the_check_detects_an_open_object() -> None:
    spec = {
        "paths": {
            "/x": {
                "post": {
                    "requestBody": {
                        "content": {
                            "application/json": {
                                "schema": {
                                    "type": "object",
                                    "properties": {"a": {"type": "object"}},
                                    "additionalProperties": False,
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    assert open_objects(spec) == ["POST /x (application/json).a"]


def test_privileged_fields_are_refused_on_every_route(harness: AppHarness) -> None:
    harness.app.state.rate_limiter = NoLimits()  # hundreds of requests from one client
    tokens: TokenService = harness.app.state.tokens
    user_id = uuid.uuid4()
    access = tokens.issue_access(
        user_id=user_id, role="user", session_id=uuid.uuid4(), tier_hint="standard"
    )
    # Staff routes answer 404 before validation outside the role/IP allow-list; open them here.
    harness.app.dependency_overrides[admin_foods.staff_only] = lambda: Principal(
        user_id=user_id, role="nutritionist", session_id=uuid.uuid4(), tier_hint="standard"
    )
    checked, wrong = 0, []
    for op in discover(harness.app.openapi()):
        if not isinstance(op.body, dict) or op.path.endswith("/webhooks/google"):
            continue  # no JSON object body (the Google webhook reads raw Pub/Sub bytes)
        for field, value in PRIVILEGED.items():
            if field in op.body:
                continue
            response = harness.client.request(
                op.method.upper(),
                op.path.format(**op.path_params),
                params=op.query,
                headers={**op.headers, "Authorization": f"Bearer {access}"},
                json={**op.body, field: value},
            )
            checked += 1
            if response.status_code != 422:
                wrong.append(f"{op.method.upper()} {op.path} +{field} -> {response.status_code}")
    assert checked >= 400
    assert wrong == []
