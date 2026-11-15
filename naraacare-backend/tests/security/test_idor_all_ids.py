"""IDOR suite (Session 16, doc 07 SEC-1.5 / T4): every route with an id in its path, called by
another user with the owner's real ids -> 404, and the owner's data is unchanged afterwards.

User A owns one of everything; user B (also STAR, same consents, so no tier or consent gate can
answer first) replays A's requests. ``test_every_id_route_is_covered`` fails when a new id route
appears without a case here or an exemption with its reason.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest

from tests.conftest import AppFactory
from tests.fakes import FakeRinModel
from tests.integration.flows import ADMIN_URL, DB_URL, PASSWORD, Flow, make_flow
from tests.integration.users import User, sql
from tests.security.payload_sweep import discover

pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs"),
]

APPLE = "0192f000-0000-7000-8000-000000000001"
CONSENTS = [
    {"purpose": "health_data", "policy_version": "0.0-draft", "granted": True},
    {"purpose": "ai_processing", "policy_version": "0.0-draft", "granted": True},
    {"purpose": "circle_sharing", "policy_version": "0.0-draft", "granted": True},
]

# Routes whose path parameter is not another user's object.
EXEMPT = {
    "GET /api/v1/foods/{food_id}": "shared food catalogue",
    "GET /api/v1/foods/barcode/{code}": "shared food catalogue (a barcode, not an id)",
    "PATCH /api/v1/admin/foods/{food_id}": "staff route: 404 for users (test_authz_matrix)",
    "PUT /api/v1/me/onboarding/steps/{step}": "a step number of the caller's own onboarding",
    "DELETE /api/v1/blocks/{user_id}": "removes an entry from the caller's own block list",
    "DELETE /api/v1/devices/{installation_id}": "covered below: B 'unregistering' A's device id",
}


def now_iso(minutes_ago: int = 5) -> str:
    return (datetime.now(UTC) - timedelta(minutes=minutes_ago)).isoformat()


@dataclass
class Owned:
    """A's objects (ids as strings) and the versions the If-Match routes need."""

    ids: dict[str, str]
    versions: dict[str, int]


def ok(response: Any, *codes: int) -> dict[str, Any]:
    assert response.status_code in (codes or (200, 201, 202, 204)), response.text
    body: dict[str, Any] = response.json() if response.content else {}
    return body


def set_username(flow: Flow, user: User) -> str:
    name = f"u{uuid.uuid4().hex[:10]}"
    ok(flow.client.put("/api/v1/me/username", headers=user.headers, json={"username": name}))
    return name


async def build(flow: Flow, a: User, c: User, c_name: str) -> Owned:
    client, h = flow.client, a.headers
    meal = ok(
        client.post(
            "/api/v1/meals",
            headers=h,
            json={
                "client_entry_id": str(uuid.uuid4()),
                "logged_at": now_iso(),
                "meal_type": "lunch",
                "source": "search",
                "items": [{"food_id": APPLE, "quantity": 1, "unit_code": "piece"}],
            },
        )
    )
    saved = ok(
        client.post(
            "/api/v1/saved-meals",
            headers=h,
            json={
                "name": "Usual lunch",
                "items": [{"food_id": APPLE, "quantity": 1, "unit_code": "piece"}],
            },
        )
    )
    intake = ok(
        client.post(
            "/api/v1/hydration/intakes",
            headers=h,
            json={
                "client_entry_id": str(uuid.uuid4()),
                "logged_at": now_iso(),
                "drink_code": "water",
                "volume_ml": 250,
                "source": "manual",
            },
        )
    )
    workout = ok(
        client.post(
            "/api/v1/workouts",
            headers=h,
            json={
                "client_entry_id": str(uuid.uuid4()),
                "workout_type": "walking",
                "duration_min": 30,
                "performed_at": now_iso(),
            },
        )
    )
    wake = datetime.now(UTC).replace(microsecond=0) - timedelta(hours=2)
    sleep = ok(
        client.post(
            "/api/v1/sleep/entries",
            headers=h,
            json={
                "client_entry_id": str(uuid.uuid4()),
                "sleep_start": (wake - timedelta(hours=7)).isoformat(),
                "wake_time": wake.isoformat(),
                "wakings": [],
            },
        )
    )
    installation = str(uuid.uuid4())
    ok(
        client.post(
            "/api/v1/devices",
            headers=h,
            json={
                "installation_id": installation,
                "platform": "android",
                "push_token": "fcm:APA91bHPRgkF3J",
                "app_version": "1.0.0",
            },
        ),
        200,
        201,
        204,
    )
    connection = ok(
        client.post("/api/v1/connections/requests", headers=h, json={"username": c_name})
    )
    circle = ok(
        client.post(
            "/api/v1/circles",
            headers=h,
            json={
                "name": "Family",
                "invitee_user_ids": [str(c.id)],
                "shared_avatars": ["hydration"],
            },
        )
    )
    circle_id = circle["circle_id"]
    link = ok(client.post(f"/api/v1/circles/{circle_id}/invite-links", headers=h, json={}))
    message = ok(
        client.post(
            f"/api/v1/circles/{circle_id}/messages",
            headers=h,
            json={"client_message_id": str(uuid.uuid4()), "body": "Hello family"},
        )
    )
    conversation = ok(client.post("/api/v1/rin/conversations", headers=h))
    action = await sql(
        "INSERT INTO ai.pending_action (user_id, conversation_id, kind, payload, expires_at)"
        ' VALUES ($1, $2, \'drink\', \'{"drink_code": "water", "volume_ml": 250}\','
        " now() + interval '1 hour') RETURNING id::text",
        a.id,
        uuid.UUID(conversation["conversation_id"]),
    )
    report = ok(
        client.post(
            "/api/v1/reports",
            headers={**h, "Idempotency-Key": str(uuid.uuid4())},
            json={
                "type": "monthly",
                "month": datetime.now(UTC).strftime("%Y-%m"),
                "sections": ["hydration"],
            },
        )
    )
    export = ok(
        client.post(
            "/api/v1/privacy/exports",
            headers={**h, "Idempotency-Key": str(uuid.uuid4())},
            json={"password": PASSWORD},
        )
    )
    return Owned(
        ids={
            "meal_id": meal["meal"]["meal_id"],
            "saved_meal_id": saved["saved_meal_id"],
            "intake_id": intake["intake"]["intake_id"],
            "workout_id": workout["workout"]["workout_id"],
            "entry_id": sleep["entry"]["entry_id"],
            "installation_id": installation,
            "connection_id": connection["connection_id"],
            "circle_id": circle["circle_id"],
            "member_id": str(c.id),
            "link_id": link["link_id"],
            "message_id": message["message_id"],
            "conversation_id": conversation["conversation_id"],
            "action_id": action[0]["id"],
            "report_id": report["report_id"],
            "export_id": export["export_id"],
        },
        versions={
            "meal_id": meal["meal"]["version"],
            "intake_id": intake["intake"]["version"],
            "entry_id": sleep["entry"]["version"],
            "workout_id": workout["workout"]["version"],
        },
    )


@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory, rin_model=FakeRinModel())


def valid_body(route: str) -> dict[str, Any] | None:
    """Bodies the owner could send successfully (the generated ones fail model checks first)."""
    if route == "PUT /api/v1/hydration/intakes/{intake_id}":
        return {"volume_ml": 300}
    if route == "PUT /api/v1/sleep/entries/{entry_id}":
        wake = datetime.now(UTC).replace(microsecond=0) - timedelta(hours=2)
        return {
            "sleep_start": (wake - timedelta(hours=6)).isoformat(),
            "wake_time": wake.isoformat(),
            "wakings": [],
        }
    return None


def id_routes(flow: Flow) -> list[tuple[str, str, dict[str, Any], dict[str, Any] | None]]:
    """(method, path template, query, body) for every route with a path parameter."""
    routes = []
    for op in discover(flow.harness.app.openapi()):
        if "{" in op.path:
            routes.append((op.method, op.path, op.query, op.body))
    return routes


def test_every_id_route_is_covered(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    names = {f"{m.upper()} {p}" for m, p, _, _ in id_routes(flow)}
    assert len(names) >= 40
    assert sorted(EXEMPT.keys() - names) == [], "stale exemptions"


async def test_another_users_ids_answer_404_everywhere(flow: Flow) -> None:
    a, b, c = (User(flow, CONSENTS) for _ in range(3))
    names = []
    for user in (a, b, c):
        await user.make_star()
        names.append(set_username(flow, user))  # Care Circle features need a username
    owned = await build(flow, a, c, names[2])
    fill: Callable[[str], str] = lambda path: path.format(**owned.ids)  # noqa: E731

    wrong = []
    for method, path, query, body in id_routes(flow):
        route = f"{method.upper()} {path}"
        if route in EXEMPT and "covered below" not in EXEMPT[route]:
            continue
        param = path[path.rindex("{") + 1 : path.rindex("}")]
        headers = dict(b.headers)
        if param in owned.versions and method in {"put", "delete"}:
            headers["If-Match"] = str(owned.versions[param])
        if method == "post":
            headers["Idempotency-Key"] = str(uuid.uuid4())
        payload = valid_body(route) or body
        response = flow.client.request(
            method.upper(), fill(path), params=query, headers=headers, json=payload
        )
        allowed = {404}
        if route == "DELETE /api/v1/devices/{installation_id}":
            allowed = {204, 404}  # idempotent "not registered to me"; A's row must survive
        if response.status_code not in allowed:
            wrong.append(f"{route} -> {response.status_code} {response.text[:120]}")
    assert wrong == [], "\n".join(wrong)

    # Nothing of A's changed: every object is still there and readable by A.
    h = a.headers
    day = datetime.now(UTC).date().isoformat()
    assert ok(flow.client.get(f"/api/v1/circles/{owned.ids['circle_id']}", headers=h))
    meals = ok(flow.client.get("/api/v1/meals", params={"date": day}, headers=h))
    assert owned.ids["meal_id"] in str(meals)
    assert ok(flow.client.get(f"/api/v1/reports/{owned.ids['report_id']}", headers=h))
    assert ok(flow.client.get(f"/api/v1/privacy/exports/{owned.ids['export_id']}", headers=h))
    rows = await sql(
        "SELECT count(*) AS n FROM notify.device WHERE installation_id = $1 AND user_id = $2",
        uuid.UUID(owned.ids["installation_id"]),
        a.id,
    )
    assert rows[0]["n"] == 1
    members = ok(flow.client.get(f"/api/v1/circles/{owned.ids['circle_id']}/members", headers=h))
    assert str(c.id) in str(members)
    status = await sql(
        "SELECT status FROM ai.pending_action WHERE id = $1", uuid.UUID(owned.ids["action_id"])
    )
    assert status[0]["status"] == "pending"
