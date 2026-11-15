"""Hydration, workouts, devices and reminder settings end to end against a real database
(Session 09, ``-m db``). The onboarding profile is the S05 Sahil-like male (70 kg, 180 cm, 30 y,
moderately active, mesomorph)."""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

import pytest

from app.domain.ai.drink_estimator import DrinkEstimate, DrinkEstimator
from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, Flow, db_only, make_flow
from tests.integration.test_meals import User
from tests.integration.users import sql

pytestmark = [
    *db_only,
    pytest.mark.skipif(ADMIN_URL is None, reason="needs NARAACARE_TEST_ADMIN_URL"),
]


class FakeModel:
    def __init__(self) -> None:
        self.names: list[str] = []

    async def estimate(self, drink_name: str) -> DrinkEstimate | None:
        self.names.append(drink_name)
        return DrinkEstimate(
            hydration_factor=0.82, confidence="high", explanation_code="milk_based"
        )


@pytest.fixture
def model() -> FakeModel:
    return FakeModel()


@pytest.fixture
def flow(app_factory: AppFactory, model: FakeModel) -> Iterator[Flow]:
    yield make_flow(app_factory, drink_estimator=DrinkEstimator(model))


def drink(user: User, code: str | None, ml: int, **extra: Any) -> Any:
    body = {
        "client_entry_id": str(extra.pop("intake_id", uuid.uuid4())),
        "logged_at": (datetime.now(UTC) - timedelta(minutes=2)).isoformat(),
        "volume_ml": ml,
        "source": extra.pop("source", "manual"),
        **({"drink_code": code} if code else {}),
        **extra,
    }
    return user.flow.client.post("/api/v1/hydration/intakes", headers=user.headers, json=body)


def test_status_before_any_drink(flow: Flow) -> None:
    user = User(flow)
    response = flow.client.get("/api/v1/hydration/status", headers=user.headers)
    assert response.status_code == 200, response.text
    status = response.json()
    assert status["state"] in {"empty", "day_ending_soon"} or status["effective_intake_ml"] == 0
    assert status["tank_ml"] == 1400  # 2 % of 70 kg
    assert status["temperature"]["c"] == 25 and status["temperature"]["stale"] is False
    assert 1500 <= status["daily_goal_ml"] <= 6000
    assert status["advanced"] is False and status["calc_version"] == "2026.1"


def test_log_replay_and_status(flow: Flow) -> None:
    user = User(flow)
    intake_id = uuid.uuid4()
    first = drink(user, "water", 250, intake_id=intake_id)
    assert first.status_code == 201, first.text
    body = first.json()
    assert body["intake"]["effective_ml"] == 250 and body["intake"]["editable"] is True
    assert body["status"]["effective_intake_ml"] == 250
    replay = drink(user, "water", 250, intake_id=intake_id)
    assert replay.status_code == 200
    assert replay.json()["status"]["effective_intake_ml"] == 250  # counted once
    milk = drink(user, "milk", 100)
    assert milk.json()["intake"]["effective_ml"] == 88
    today = body["intake"]["date"]
    listed = flow.client.get(
        "/api/v1/hydration/intakes", params={"date": today}, headers=user.headers
    )
    assert [i["drink_code"] for i in listed.json()["items"]] == ["water", "milk"]


def test_swipe_down_rules(flow: Flow) -> None:
    user = User(flow)
    swipe = drink(user, "water", -100, source="swipe")
    assert swipe.status_code == 422 and swipe.json()["error"]["code"] == "WATER_BELOW_ZERO"
    assert drink(user, "water", 100, source="swipe").status_code == 201
    assert drink(user, "water", -100, source="swipe").status_code == 201
    assert drink(user, "tea", -100, source="swipe").status_code == 422  # schema: water only


def test_tier_rules_and_upgrade_feature(flow: Flow) -> None:
    user = User(flow)
    coffee = drink(user, "coffee", 200)
    assert coffee.status_code == 403
    assert coffee.json()["error"] == {
        **coffee.json()["error"],
        "code": "UPGRADE_REQUIRED",
        "feature": "premium_drinks",
    }
    temp = flow.client.put(
        "/api/v1/hydration/temperature", headers=user.headers, json={"temperature_c": 35}
    )
    assert temp.status_code == 403 and temp.json()["error"]["feature"] == "advanced_hydration"
    workout = flow.client.post(
        "/api/v1/workouts",
        headers=user.headers,
        json={
            "client_entry_id": str(uuid.uuid4()),
            "workout_type": "running",
            "duration_min": 30,
            "performed_at": datetime.now(UTC).isoformat(),
        },
    )
    assert workout.status_code == 403
    estimate = flow.client.post(
        "/api/v1/hydration/custom-drinks/estimate", headers=user.headers, json={"name": "Lassi"}
    )
    assert estimate.status_code == 403
    drinks = flow.client.get("/api/v1/hydration/drinks", headers=user.headers).json()
    assert {d["drink_code"]: d["locked"] for d in drinks["drinks"]}["coffee"] is True


async def test_star_temperature_workout_and_allowance(flow: Flow) -> None:
    user = User(flow)
    await user.make_star()
    before = flow.client.get("/api/v1/hydration/status", headers=user.headers).json()
    assert before["advanced"] is True and before["temperature"]["stale"] is True
    hot = flow.client.put(
        "/api/v1/hydration/temperature", headers=user.headers, json={"temperature_c": 35}
    )
    assert hot.status_code == 200, hot.text
    assert hot.json()["daily_goal_ml"] > before["daily_goal_ml"]
    assert hot.json()["temperature"]["stale"] is False

    run = flow.client.post(
        "/api/v1/workouts",
        headers=user.headers,
        json={
            "client_entry_id": str(uuid.uuid4()),
            "workout_type": "running",
            "duration_min": 60,
            "performed_at": (datetime.now(UTC) - timedelta(minutes=1)).isoformat(),
        },
    )
    assert run.status_code == 201, run.text
    out = run.json()
    assert (out["sweat_ml"], out["kcal"]) == (875.0, 686)  # 12.5 x 70; 9.8 x 70
    assert out["status"]["workout_sweat_ml"] == 875
    summary = flow.client.get(
        "/api/v1/nutrition/daily-summary",
        params={"date": out["workout"]["date"]},
        headers=user.headers,
    ).json()
    assert summary["exercise_kcal"] == 686
    assert summary["effective_allowance_kcal"] == summary["target_kcal"] + 686

    workout_id = out["workout"]["workout_id"]
    stale = flow.client.delete(
        f"/api/v1/workouts/{workout_id}", headers={**user.headers, "If-Match": "9"}
    )
    assert stale.status_code == 409 and stale.json()["error"]["current"]["workout_id"] == workout_id
    gone = flow.client.delete(
        f"/api/v1/workouts/{workout_id}", headers={**user.headers, "If-Match": "1"}
    )
    assert gone.status_code == 204


async def test_custom_drink_estimate_consent_and_save(flow: Flow, model: FakeModel) -> None:
    user = User(flow)
    await user.make_star()
    # Onboarding left AI consent off: the default is offered and nothing is sent to the model.
    default = flow.client.post(
        "/api/v1/hydration/custom-drinks/estimate",
        headers=user.headers,
        json={"name": "Banana Shake"},
    ).json()
    assert default == {
        "hydration_factor": 0.85,
        "source": "default",
        "explanation_code": "ai_consent_missing",
    }
    assert model.names == []
    granted = flow.client.post(
        "/api/v1/privacy/consents",
        headers=user.headers,
        json={"purpose": "ai_processing", "policy_version": "0.0-draft", "granted": True},
    )
    assert granted.status_code in {200, 201, 204}, granted.text
    ai = flow.client.post(
        "/api/v1/hydration/custom-drinks/estimate",
        headers=user.headers,
        json={"name": "Banana Shake"},
    ).json()
    assert ai == {"hydration_factor": 0.82, "source": "ai", "explanation_code": "milk_based"}
    assert model.names == ["Banana Shake"]

    saved = flow.client.post(
        "/api/v1/hydration/custom-drinks",
        headers=user.headers,
        json={"name": "Banana Shake", "hydration_factor": 0.82, "source": "ai"},
    )
    assert saved.status_code == 201, saved.text
    again = flow.client.post(
        "/api/v1/hydration/custom-drinks",
        headers=user.headers,
        json={"name": "banana shake", "hydration_factor": 0.8},
    )
    assert again.status_code == 409 and again.json()["error"]["code"] == "ALREADY_EXISTS"
    logged = drink(user, None, 300, custom_drink_id=saved.json()["custom_drink_id"])
    assert logged.status_code == 201 and logged.json()["intake"]["effective_ml"] == 246
    assert logged.json()["intake"]["label"] == "Banana Shake"


def test_edit_conflict_window_and_idor(flow: Flow) -> None:
    user, other = User(flow), User(flow)
    first = drink(user, "water", 100).json()["intake"]
    second = drink(user, "tea", 200).json()["intake"]
    third = drink(user, "water", 300).json()["intake"]
    closed = flow.client.put(
        f"/api/v1/hydration/intakes/{first['intake_id']}",
        headers={**user.headers, "If-Match": "1"},
        json={"volume_ml": 150},
    )
    assert closed.status_code == 403 and closed.json()["error"]["code"] == "EDIT_WINDOW_CLOSED"
    stale = flow.client.put(
        f"/api/v1/hydration/intakes/{second['intake_id']}",
        headers={**user.headers, "If-Match": "5"},
        json={"volume_ml": 150},
    )
    assert stale.status_code == 409
    assert stale.json()["error"]["current"]["volume_ml"] == 200
    edited = flow.client.put(
        f"/api/v1/hydration/intakes/{second['intake_id']}",
        headers={**user.headers, "If-Match": "1"},
        json={"volume_ml": 150, "drink_code": "milk"},
    )
    assert edited.status_code == 200, edited.text
    assert (
        edited.json()["intake"]["effective_ml"] == 132 and edited.json()["intake"]["version"] == 2
    )
    for method in ("put", "delete"):
        response = getattr(flow.client, method)(
            f"/api/v1/hydration/intakes/{third['intake_id']}",
            headers={**other.headers, "If-Match": "1"},
            **({"json": {"volume_ml": 1}} if method == "put" else {}),
        )
        assert response.status_code == 404
    missing = flow.client.put(
        "/api/v1/hydration/intakes/not-a-uuid", headers={**user.headers, "If-Match": "1"}, json={}
    )
    assert missing.status_code == 422


async def test_devices_preferences_and_reminders(flow: Flow) -> None:
    user = User(flow)
    installation = str(uuid.uuid4())
    token = "fcm-token-" + "x" * 40
    registered = flow.client.post(
        "/api/v1/devices",
        headers=user.headers,
        json={
            "installation_id": installation,
            "platform": "android",
            "push_token": token,
            "app_version": "1.0.0+1",
        },
    )
    assert registered.status_code == 201, registered.text
    rows = await sql(
        "SELECT installation_id, push_token FROM notify.device WHERE user_id = $1", user.id
    )
    assert len(rows) == 1
    assert rows[0]["push_token"] == token  # plain text (owner decision 2026-11-03)
    assert str(rows[0]["installation_id"]) == installation
    revoked = flow.client.delete(f"/api/v1/devices/{installation}", headers=user.headers)
    assert revoked.status_code == 204
    rows = await sql("SELECT push_token, revoked_at FROM notify.device WHERE user_id = $1", user.id)
    assert rows[0]["push_token"] is None and rows[0]["revoked_at"] is not None

    prefs = flow.client.get("/api/v1/me/notification-preferences", headers=user.headers).json()
    assert len(prefs) == 12 and prefs["daily_checkin"] is False
    prefs["daily_checkin"] = True
    saved = flow.client.put("/api/v1/me/notification-preferences", headers=user.headers, json=prefs)
    assert saved.status_code == 200 and saved.json()["daily_checkin"] is True
    partial = flow.client.put(
        "/api/v1/me/notification-preferences", headers=user.headers, json={"daily_checkin": True}
    )
    assert partial.status_code == 422

    reminders = flow.client.get("/api/v1/me/reminders", headers=user.headers).json()["reminders"]
    assert [r["saved"] for r in reminders] == [False] * 5
    put = flow.client.put(
        "/api/v1/me/reminders",
        headers=user.headers,
        json={
            "reminders": [
                {"type": "hydration", "enabled": True, "interval_min": 90},
                {"type": "nutrition", "enabled": True, "times": ["20:00", "08:30"]},
            ]
        },
    )
    assert put.status_code == 200, put.text
    by_type = {r["type"]: r for r in put.json()["reminders"]}
    assert by_type["hydration"]["interval_min"] == 90 and by_type["hydration"]["saved"] is True
    assert by_type["nutrition"]["times"] == ["08:30", "20:00"]


def test_past_day_status(flow: Flow) -> None:
    user = User(flow)
    yesterday = (datetime.now(UTC) - timedelta(days=1)).date().isoformat()
    response = flow.client.get(
        "/api/v1/hydration/status", params={"date": yesterday}, headers=user.headers
    )
    assert response.status_code == 200
    assert response.json()["state"] != "day_ending_soon"
    assert Decimal(str(response.json()["level_pct"])) >= 0
