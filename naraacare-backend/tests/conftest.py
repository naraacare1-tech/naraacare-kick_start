from __future__ import annotations

from collections.abc import AsyncIterator, Callable, Iterator, Mapping, Sequence
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path

import pytest
from fastapi import APIRouter, FastAPI
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.core.memory_store import MemoryStore
from app.main import create_app
from app.repositories.audit import SecurityEvent

ROOT = Path(__file__).resolve().parents[1]

SetEnv = Callable[..., None]
MakeSettings = Callable[..., Settings]


def parse_env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip()
    return values


@pytest.fixture
def example_env() -> dict[str, str]:
    """Values from .env.example — the dummy configuration every developer starts from."""
    return parse_env_file(ROOT / ".env.example")


@pytest.fixture
def set_env(monkeypatch: pytest.MonkeyPatch, tmp_path: Path, example_env: dict[str, str]) -> SetEnv:
    """Put .env.example values (plus overrides; None = unset) into the process environment.

    Tests run from an empty directory so a developer's real .env is never read.
    """
    monkeypatch.chdir(tmp_path)

    def _set(**overrides: str | None) -> None:
        for key, value in {**example_env, **overrides}.items():
            if value is None:
                monkeypatch.delenv(key, raising=False)
            else:
                monkeypatch.setenv(key, value)

    return _set


@pytest.fixture
def make_settings(set_env: SetEnv) -> MakeSettings:
    def _make(**overrides: str | None) -> Settings:
        set_env(**overrides)
        return Settings()

    return _make


# --------------------------------------------------------------------------- app fixtures (S04)
class RecordingEvents:
    """Stands in for SecurityEventWriter: records events instead of writing them to the DB."""

    def __init__(self) -> None:
        self.events: list[SecurityEvent] = []

    def submit(self, event: SecurityEvent) -> None:
        self.events.append(event)

    def start(self) -> None:
        return None

    async def stop(self) -> None:
        return None


class UnavailableDb:
    """A Database whose every transaction fails: the readiness probe must report it."""

    @asynccontextmanager
    async def transaction(self, **_: object) -> AsyncIterator[None]:
        raise ConnectionRefusedError("database down")
        yield  # pragma: no cover

    async def dispose(self) -> None:
        return None


@dataclass
class AppHarness:
    app: FastAPI
    client: TestClient
    events: RecordingEvents
    store: MemoryStore


AppFactory = Callable[..., AppHarness]


@pytest.fixture
def app_factory(make_settings: MakeSettings) -> Iterator[AppFactory]:
    """Build the real app (all middleware) with the in-memory store and recorded security events."""
    clients: list[TestClient] = []

    def _build(
        *,
        routers: Sequence[APIRouter] = (),
        db: object | None = None,
        state: Mapping[str, object] | None = None,
        **overrides: str | None,
    ) -> AppHarness:
        """``state`` pre-sets app.state attributes (e.g. ``email``, ``password_hasher``, ``oauth``);
        start-up keeps whatever is already there."""
        settings = make_settings(ALLOWED_HOSTS="testserver", **overrides)
        app = create_app(settings)
        for router in routers:
            app.include_router(router, prefix="/api/v1")
        events = RecordingEvents()
        store = MemoryStore()
        app.state.store = store
        app.state.db = db or UnavailableDb()
        app.state.security_events = events
        for name, value in (state or {}).items():
            setattr(app.state, name, value)
        client = TestClient(app, raise_server_exceptions=False)
        client.__enter__()
        clients.append(client)
        return AppHarness(app=app, client=client, events=events, store=store)

    yield _build
    for client in clients:
        client.__exit__(None, None, None)
