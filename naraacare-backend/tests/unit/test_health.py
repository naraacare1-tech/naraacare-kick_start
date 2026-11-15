from __future__ import annotations

from fastapi.testclient import TestClient

from app.main import create_app
from tests.conftest import MakeSettings


def test_live_returns_ok(make_settings: MakeSettings) -> None:
    client = TestClient(create_app(make_settings(ALLOWED_HOSTS="testserver")))

    response = client.get("/api/v1/health/live")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_docs_disabled_when_flag_off(make_settings: MakeSettings) -> None:
    settings = make_settings(ALLOWED_HOSTS="testserver", API_DOCS_ENABLED="false")
    client = TestClient(create_app(settings))

    assert client.get("/api/v1/docs").status_code == 404
    assert client.get("/api/v1/docs/openapi.json").status_code == 404


def test_unknown_host_rejected(make_settings: MakeSettings) -> None:
    client = TestClient(create_app(make_settings(ALLOWED_HOSTS="api.example.internal")))

    assert client.get("/api/v1/health/live").status_code == 400
