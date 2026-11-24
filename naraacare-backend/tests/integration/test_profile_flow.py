"""Onboarding, targets, profile, settings, username, consents and entitlements (doc 04 2.2/2.13)."""

from __future__ import annotations

import json
from decimal import Decimal
from typing import Any

import pytest

from app.domain.common.calc_context import CalcContext
from app.repositories import reference_repo
from tests.calc_seed import SEED
from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, Flow, bearer, db_only, make_flow, real_db

pytestmark = db_only

STEPS: dict[int, dict[str, Any]] = {
    1: {"biological_sex": "male", "avatar_code": "male_mesomorph", "full_name": "Sahil Verma"},
    2: {"height_cm": 180},
    3: {"weight_kg": 70, "weight_goal": "standard_gain"},
    4: {"target_weight_kg": 74.5, "medical_condition_codes": ["hypertension", "allergy_peanut"]},
    5: {"age_years": 30, "activity_level": "moderately_active"},
    6: {"body_type": "mesomorph"},
}
CONSENTS = [
    {"purpose": "health_data", "policy_version": "0.0-draft", "granted": True},
    {"purpose": "ai_processing", "policy_version": "0.0-draft", "granted": False},
]


def onboard(flow: Flow, headers: dict[str, str], steps: dict[int, dict[str, Any]] = STEPS) -> None:
    for step, body in steps.items():
        response = flow.client.put(
            f"/api/v1/me/onboarding/steps/{step}", headers=headers, json=body
        )
        assert response.status_code == 200, (step, response.text)
        assert response.json()["current_step"] == step


async def test_calc_context_in_the_database_matches_the_unit_test_seed() -> None:
    db = real_db()
    try:
        raw = await db.run(reference_repo.calc_context, readonly=True)
    finally:
        await db.dispose()
    live = CalcContext.from_db(raw)
    seed = CalcContext.from_db(json.dumps(SEED))
    assert live.calc_version == seed.calc_version
    assert {k: live.constants[k] for k in seed.constants} == dict(seed.constants)
    assert live.activity_levels == seed.activity_levels
    assert live.body_types == seed.body_types
    assert live.weight_goals == seed.weight_goals
    assert live.bmi_categories == seed.bmi_categories
    assert seed.medical_condition_codes <= live.medical_condition_codes


def test_full_onboarding_preview_equals_completed_targets(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    _, pair = flow.new_user()
    headers = bearer(pair)
    early = flow.client.post(
        "/api/v1/me/onboarding/complete", headers=headers, json={"consents": CONSENTS}
    )
    assert early.status_code == 409 and early.json()["error"]["code"] == "ONBOARDING_INCOMPLETE"
    onboard(flow, headers, {k: STEPS[k] for k in (1, 2, 3)})
    resume = flow.client.get("/api/v1/me/onboarding", headers=headers).json()
    assert resume["current_step"] == 3 and resume["completed"] is False
    assert resume["data_so_far"]["full_name"] == "Sahil Verma"
    onboard(flow, headers, {k: STEPS[k] for k in (4, 5, 6)})

    preview = flow.client.post("/api/v1/calculations/preview", headers=headers).json()
    assert preview["targets"] == {  # doc 06 example 1
        "kcal": 3104,
        "carbs_g": 427,
        "fat_g": 86,
        "protein_g": 155,
        "safety_override": False,
    }
    assert Decimal(str(preview["bmi"])) == Decimal("21.6") and preview["bmi_category"] == "normal"
    assert preview["healthy_weight_range_kg"] == [60, 81]

    done = flow.client.post(
        "/api/v1/me/onboarding/complete", headers=headers, json={"consents": CONSENTS}
    )
    assert done.status_code == 201, done.text
    targets = done.json()
    assert targets["nutrition"] == preview["targets"]
    assert targets["water_need_ml"] == preview["water_need_ml"]
    assert flow.client.get("/api/v1/me/targets/today", headers=headers).json() == targets
    again = flow.client.post(
        "/api/v1/me/onboarding/complete", headers=headers, json={"consents": CONSENTS}
    )
    assert again.status_code == 409

    me = flow.client.get("/api/v1/me", headers=headers).json()
    assert me["onboarding"] == {"current_step": 6, "completed": True}
    assert me["profile"]["full_name"] == "Sahil Verma"
    assert me["profile"]["medical_condition_codes"] == ["allergy_peanut", "hypertension"]
    assert me["settings"]["sleep_goal_min"] == 480
    login = flow.client.post(
        "/api/v1/auth/login",
        json={"email": me["email"], "password": "Correct1Horse", "installation_id": me["user_id"]},
    )
    assert login.json()["onboarding_required"] is False


def test_onboarding_rules(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    _, pair = flow.new_user()
    headers = bearer(pair)
    put = flow.client.put
    skipped = put("/api/v1/me/onboarding/steps/2", headers=headers, json=STEPS[2])
    assert skipped.status_code == 422  # cannot skip step 1
    extra = put(
        "/api/v1/me/onboarding/steps/1", headers=headers, json={**STEPS[1], "height_cm": 180}
    )
    assert extra.status_code == 422 and extra.json()["error"]["fields"] == ["height_cm"]
    mismatch = put(
        "/api/v1/me/onboarding/steps/1",
        headers=headers,
        json={**STEPS[1], "avatar_code": "female_mesomorph"},
    )
    assert mismatch.status_code == 422
    onboard(flow, headers, {1: STEPS[1], 2: {"height_cm": 170}})
    blocked = put(
        "/api/v1/me/onboarding/steps/3",
        headers=headers,
        json={"weight_kg": 50, "weight_goal": "mild_loss"},  # BMI 17.3: loss goals blocked
    )
    assert blocked.status_code == 422 and blocked.json()["error"]["code"] == "GOAL_NOT_ALLOWED"
    underage = put("/api/v1/me/onboarding/steps/5", headers=headers, json={"age_years": 17})
    assert underage.status_code == 422
    unknown_code = put(
        "/api/v1/me/onboarding/steps/4",
        headers=headers,
        json={"target_weight_kg": 60, "medical_condition_codes": ["made_up"]},
    )
    assert unknown_code.status_code == 422
    options = flow.client.get(
        "/api/v1/me/goal-options", headers=headers, params={"weight_kg": 50, "height_cm": 170}
    ).json()
    assert options["category"] == "underweight"
    assert "mild_loss" not in options["allowed_goals"] and "maintain" in options["allowed_goals"]


def test_profile_update_recomputes_today_only_and_rejects_mass_assignment(
    app_factory: AppFactory,
) -> None:
    flow = make_flow(app_factory)
    _, pair = flow.new_user()
    headers = bearer(pair)
    onboard(flow, headers)
    flow.client.post("/api/v1/me/onboarding/complete", headers=headers, json={"consents": CONSENTS})
    patch = flow.client.patch("/api/v1/me/profile", headers=headers, json={"weight_kg": 80})
    assert patch.status_code == 200, patch.text
    assert patch.json()["targets_today"]["nutrition"]["kcal"] == 2316  # BMR 1780 -> 1816 + 500
    name_only = flow.client.patch(
        "/api/v1/me/profile", headers=headers, json={"full_name": "Sahil V"}
    )
    assert name_only.json()["targets_today"] is None
    assert name_only.json()["me"]["profile"]["full_name"] == "Sahil V"
    for field, value in (("role", "admin"), ("tier", "star"), ("user_id", pair["refresh_token"])):
        sneaky = flow.client.patch("/api/v1/me/profile", headers=headers, json={field: value})
        assert sneaky.status_code == 422, field
    empty = flow.client.patch("/api/v1/me/profile", headers=headers, json={})
    assert empty.status_code == 422


def test_settings_username_entitlements_and_consents(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    _, first = flow.new_user()
    _, second = flow.new_user()
    for pair in (first, second):
        onboard(flow, bearer(pair))
    settings = {
        "height_unit": "ft_in",
        "weight_unit": "lb",
        "temperature_unit": "f",
        "timezone": "Asia/Dubai",
        "locale": "en-IN",
        "sleep_start_local": "22:30",
        "wake_local": "06:30",
        "biometric_lock": True,
    }
    assert (
        flow.client.put("/api/v1/me/settings", headers=bearer(first), json=settings).status_code
        == 204
    )
    me = flow.client.get("/api/v1/me", headers=bearer(first)).json()
    assert me["settings"]["timezone"] == "Asia/Dubai" and me["settings"]["biometric_lock"] is True

    name = f"sahil.{first['refresh_token'][:6].lower().replace('-', 'x').replace('_', 'x')}"
    available = flow.client.get(
        "/api/v1/usernames/availability", headers=bearer(second), params={"username": name}
    )
    assert available.json() == {"available": True}
    assert (
        flow.client.put(
            "/api/v1/me/username", headers=bearer(first), json={"username": name}
        ).status_code
        == 204
    )
    taken = flow.client.put("/api/v1/me/username", headers=bearer(second), json={"username": name})
    assert taken.status_code == 409 and taken.json()["error"]["code"] == "USERNAME_TAKEN"
    too_soon = flow.client.put(
        "/api/v1/me/username", headers=bearer(first), json={"username": name + "2"}
    )
    assert too_soon.status_code == 403
    assert flow.client.get(
        "/api/v1/usernames/availability", headers=bearer(second), params={"username": name}
    ).json() == {"available": False}

    plan = flow.client.get("/api/v1/me/entitlements", headers=bearer(first)).json()
    assert plan["tier"] == "standard" and plan["features"]["sleep"] is False
    assert plan["limits"]["meal_logs_per_day"] == 4

    granted = {"purpose": "marketing", "policy_version": "0.0-draft", "granted": True}
    assert (
        flow.client.post(
            "/api/v1/privacy/consents", headers=bearer(first), json=granted
        ).status_code
        == 201
    )
    withdrawn = {**granted, "granted": False}
    assert (
        flow.client.post(
            "/api/v1/privacy/consents", headers=bearer(first), json=withdrawn
        ).status_code
        == 201
    )
    consents = {
        c["purpose"]: c
        for c in flow.client.get("/api/v1/privacy/consents", headers=bearer(first)).json()[
            "consents"
        ]
    }
    assert consents["marketing"]["granted"] is False
    assert consents["terms"]["granted"] is True  # recorded at sign-up
    # Each user only ever sees their own data: there are no ids to swap in these routes.
    other = flow.client.get("/api/v1/privacy/consents", headers=bearer(second)).json()["consents"]
    assert "marketing" not in {c["purpose"] for c in other}


def test_reference_endpoints(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    boot = flow.client.get("/api/v1/reference/bootstrap")
    assert boot.status_code == 200 and boot.headers["Cache-Control"] == "public, max-age=3600"
    assert {"activity_levels", "body_types", "medical_conditions"} <= boot.json().keys()
    cached = flow.client.get(
        "/api/v1/reference/bootstrap", headers={"If-None-Match": boot.headers["ETag"]}
    )
    assert cached.status_code == 304
    policies = flow.client.get("/api/v1/reference/policies").json()["policies"]
    assert {p["type"] for p in policies} == {"terms", "privacy", "licenses"}


def test_endpoints_require_a_token(app_factory: AppFactory) -> None:
    flow = make_flow(app_factory)
    for method, path in (
        ("get", "/api/v1/me"),
        ("patch", "/api/v1/me/profile"),
        ("get", "/api/v1/me/onboarding"),
        ("post", "/api/v1/calculations/preview"),
        ("get", "/api/v1/me/entitlements"),
        ("get", "/api/v1/privacy/consents"),
        ("post", "/api/v1/auth/logout"),
    ):
        response = getattr(flow.client, method)(path, headers={"Authorization": "Bearer nope"})
        assert response.status_code == 401, path


@pytest.mark.skipif(ADMIN_URL is None, reason="NARAACARE_TEST_ADMIN_URL not set")
async def test_name_and_conditions_are_stored_in_plain_text(app_factory: AppFactory) -> None:
    import asyncpg  # noqa: PLC0415

    flow = make_flow(app_factory)
    _, pair = flow.new_user()
    onboard(flow, bearer(pair), {1: STEPS[1], 2: STEPS[2], 3: STEPS[3], 4: STEPS[4]})
    assert ADMIN_URL is not None
    conn = await asyncpg.connect(ADMIN_URL)
    try:
        rows = await conn.fetch("SELECT full_name, medical_conditions FROM app.user_profile")
    finally:
        await conn.close()
    # Plain text since the owner decision of 2026-11-03.
    assert any(r["full_name"] and "Sahil" in r["full_name"] for r in rows)
    assert any("hypertension" in (r["medical_conditions"] or []) for r in rows)
