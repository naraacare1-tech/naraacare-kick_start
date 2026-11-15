"""Staff routes need the role AND an address in STAFF_IP_ALLOWLIST (doc 07 SEC-1.5)."""

from __future__ import annotations

import uuid
from typing import Annotated

import pytest
from fastapi import APIRouter, Depends
from fastapi.testclient import TestClient

from app.core.config import SettingsLoadError
from app.core.security.authz import Principal, require_staff
from tests.conftest import AppFactory, MakeSettings

router = APIRouter()


@router.get("/staff-probe")
async def probe(
    principal: Annotated[Principal, Depends(require_staff("nutritionist", "admin"))],
) -> dict[str, str]:
    return {"role": principal.role}


def call(app_factory: AppFactory, role: str, address: str, allowlist: str) -> int:
    harness = app_factory(routers=[router], STAFF_IP_ALLOWLIST=allowlist)
    token = harness.app.state.tokens.issue_access(
        user_id=uuid.uuid4(), role=role, session_id=uuid.uuid4(), tier_hint="standard"
    )
    with TestClient(harness.app, client=(address, 50000), raise_server_exceptions=False) as client:
        response = client.get(
            "/api/v1/staff-probe",
            headers={"Authorization": f"Bearer {token}", "Host": "testserver"},
        )
    return response.status_code


@pytest.mark.parametrize(
    ("role", "address", "allowlist", "status"),
    [
        ("nutritionist", "10.1.2.3", "10.0.0.0/8", 200),
        ("admin", "::1", "127.0.0.1/32,::1/128", 200),
        ("nutritionist", "192.168.1.5", "10.0.0.0/8", 404),  # outside the network
        ("user", "10.1.2.3", "10.0.0.0/8", 404),  # wrong role
        ("nutritionist", "10.1.2.3", "", 404),  # empty list = closed
    ],
)
def test_role_and_network_are_both_required(
    app_factory: AppFactory, role: str, address: str, allowlist: str, status: int
) -> None:
    assert call(app_factory, role, address, allowlist) == status


def test_the_allowlist_must_hold_networks(make_settings: MakeSettings) -> None:
    with pytest.raises((SettingsLoadError, ValueError)):
        make_settings(STAFF_IP_ALLOWLIST="10.0.0.0/8,not-a-network")
