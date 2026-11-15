"""WebSocket limits (Session 16, doc 04 section 2.9, doc 07 T19 / T27).

The socket opens only with a fresh single-use ticket; frames are capped at 8 KB and 20 per 10 s;
binary and oversized frames close it; unknown frames are ignored and never echoed; and a revoked
session loses its sockets at once (logout, logout-all, password change keeps only the caller's).
Rin's SSE inputs are ordinary JSON bodies (payload sweep, rate limit ``rin_chat``).
"""

from __future__ import annotations

import contextlib
import json
import uuid
from collections.abc import Iterator

import pytest
from anyio import ClosedResourceError
from starlette.testclient import WebSocketTestSession
from starlette.websockets import WebSocketDisconnect

from app.api.v1.routers.chat import FRAME_BUDGET, MAX_FRAME_CHARS
from app.core.security.tokens import TokenService
from app.domain.social.realtime import TicketStore
from tests.conftest import AppFactory, AppHarness
from tests.integration.flows import ADMIN_URL, DB_URL, PASSWORD, Flow, bearer, make_flow


@pytest.fixture
def harness(app_factory: AppFactory) -> AppHarness:
    return app_factory()


def headers(harness: AppHarness, session_id: uuid.UUID | None = None) -> dict[str, str]:
    tokens: TokenService = harness.app.state.tokens
    token = tokens.issue_access(
        user_id=uuid.uuid4(), role="user", session_id=session_id or uuid.uuid4(), tier_hint="star"
    )
    return {"Authorization": f"Bearer {token}"}


def ticket(harness: AppHarness, auth: dict[str, str]) -> str:
    response = harness.client.post("/api/v1/realtime/ticket", headers=auth)
    assert response.status_code == 200, response.text
    return str(response.json()["ticket"])


def closed_with(session: WebSocketTestSession) -> int:
    with pytest.raises(WebSocketDisconnect) as info:
        for _ in range(FRAME_BUDGET + 5):
            session.receive_text()
    return info.value.code


@pytest.mark.parametrize("value", [None, "", "x" * 65, "not-a-ticket", "<script>"])
def test_socket_refused_without_a_valid_ticket(harness: AppHarness, value: str | None) -> None:
    url = "/api/v1/ws" if value is None else f"/api/v1/ws?ticket={value}"
    with pytest.raises(WebSocketDisconnect) as info, harness.client.websocket_connect(url):
        pass
    assert info.value.code == 4401


def test_ticket_is_single_use(harness: AppHarness) -> None:
    value = ticket(harness, headers(harness))
    with harness.client.websocket_connect(f"/api/v1/ws?ticket={value}") as ws:
        ws.send_text(json.dumps({"type": "ping"}))
        assert ws.receive_json() == {"type": "pong"}
    with (
        pytest.raises(WebSocketDisconnect) as info,
        harness.client.websocket_connect(f"/api/v1/ws?ticket={value}"),
    ):
        pass
    assert info.value.code == 4401


def test_expired_ticket_is_refused() -> None:
    now = [1000.0]
    store = TicketStore(clock=lambda: now[0])
    value = store.issue(uuid.uuid4(), uuid.uuid4())
    now[0] += 31
    assert store.redeem(value) is None
    assert store.redeem(value) is None


def test_ticket_route_needs_a_token(harness: AppHarness) -> None:
    assert harness.client.post("/api/v1/realtime/ticket").status_code == 401


def test_oversized_frame_closes_the_socket(harness: AppHarness) -> None:
    value = ticket(harness, headers(harness))
    with harness.client.websocket_connect(f"/api/v1/ws?ticket={value}") as ws:
        ws.send_text(json.dumps({"type": "ping", "pad": "x" * MAX_FRAME_CHARS}))
        assert closed_with(ws) == 1009


def test_binary_frame_closes_the_socket(harness: AppHarness) -> None:
    value = ticket(harness, headers(harness))
    with harness.client.websocket_connect(f"/api/v1/ws?ticket={value}") as ws:
        ws.send_bytes(b"\x00\x01")
        assert closed_with(ws) == 1003


def test_frame_flood_closes_the_socket(harness: AppHarness) -> None:
    value = ticket(harness, headers(harness))
    with harness.client.websocket_connect(f"/api/v1/ws?ticket={value}") as ws:
        for _ in range(FRAME_BUDGET):
            ws.send_text(json.dumps({"type": "ping"}))
            assert ws.receive_json() == {"type": "pong"}
        ws.send_text(json.dumps({"type": "ping"}))
        assert closed_with(ws) == 1008


@pytest.mark.parametrize(
    "frame",
    [
        '{"type": "<script>alert(1)</script>"}',
        '{"type": "message.created", "body": "<img src=x onerror=alert(1)>"}',
        '{"type": "typing", "circle_id": "not-a-uuid"}',
        "not json at all <svg onload=alert(1)>",
        '{"type": "ping", "extra": "javascript:alert(1)"}',
    ],
)
def test_unknown_frames_are_ignored_and_never_echoed(harness: AppHarness, frame: str) -> None:
    value = ticket(harness, headers(harness))
    with harness.client.websocket_connect(f"/api/v1/ws?ticket={value}") as ws:
        ws.send_text(frame)
        ws.send_text(json.dumps({"type": "ping"}))
        reply = ws.receive_text()
        assert json.loads(reply) == {"type": "pong"}
        assert "script" not in reply and "alert" not in reply


# --------------------------------------------------------------------------- revoked sessions
@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory)


def open_socket(flow: Flow, pair: dict[str, str]) -> WebSocketTestSession:
    response = flow.client.post("/api/v1/realtime/ticket", headers=bearer(pair))
    assert response.status_code == 200, response.text
    session = flow.client.websocket_connect(f"/api/v1/ws?ticket={response.json()['ticket']}")
    opened: WebSocketTestSession = session.__enter__()
    return opened


def still_open(ws: WebSocketTestSession) -> bool:
    """A ping answered with pong; a socket the server closed fails on send or receive."""
    try:
        ws.send_text(json.dumps({"type": "ping"}))
        return bool(ws.receive_json() == {"type": "pong"})
    except (WebSocketDisconnect, ClosedResourceError, RuntimeError):
        return False


def close(*sockets: WebSocketTestSession) -> None:
    for ws in sockets:
        with contextlib.suppress(Exception):
            ws.__exit__(None, None, None)


@pytest.mark.db
@pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")
def test_revoked_sessions_lose_their_sockets(flow: Flow) -> None:
    address, first = flow.new_user()
    second = flow.login(address, installation=uuid.uuid4()).json()
    third = flow.login(address, installation=uuid.uuid4()).json()
    ws1, ws2, ws3 = open_socket(flow, first), open_socket(flow, second), open_socket(flow, third)
    try:
        # Logout ends exactly that session's socket.
        assert flow.client.post("/api/v1/auth/logout", headers=bearer(first)).status_code == 204
        assert not still_open(ws1)
        assert still_open(ws2) and still_open(ws3)

        # A password change keeps the caller's socket and ends every other one.
        changed = flow.client.post(
            "/api/v1/auth/password/change",
            headers=bearer(third),
            json={
                "current_password": PASSWORD,
                "new_password": "Another2Horse",
                "confirm_password": "Another2Horse",
            },
        )
        assert changed.status_code in {200, 204}, changed.text
        assert still_open(ws3)
        assert not still_open(ws2)

        # Logout-all ends the rest.
        assert flow.client.post("/api/v1/auth/logout-all", headers=bearer(third)).status_code == 204
        assert not still_open(ws3)
    finally:
        close(ws1, ws2, ws3)
