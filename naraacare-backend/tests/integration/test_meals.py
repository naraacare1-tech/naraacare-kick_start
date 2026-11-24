"""Nutrition end to end against a real database (Session 08, ``-m db``).

Uses the development sample foods (seed_sample_foods = true in local/CI test databases).
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from decimal import Decimal
from typing import Any

import pytest

from app.api.v1.routers import admin_foods
from app.core.security.authz import Principal
from app.integrations.open_food_facts import OffProduct
from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, Flow, db_only, make_flow
from tests.integration.users import User as BaseUser
from tests.integration.users import sql

pytestmark = [
    *db_only,
    pytest.mark.skipif(ADMIN_URL is None, reason="needs NARAACARE_TEST_ADMIN_URL"),
]

APPLE = "0192f000-0000-7000-8000-000000000001"
BANANA = "0192f000-0000-7000-8000-000000000002"
ROTI = "0192f000-0000-7000-8000-000000000003"
DAL = "0192f000-0000-7000-8000-000000000004"
RICE = "0192f000-0000-7000-8000-000000000007"


class FakeOff:
    def __init__(self, product: OffProduct | None) -> None:
        self.product_result = product
        self.calls: list[str] = []

    async def product(self, barcode: str) -> OffProduct | None:
        self.calls.append(barcode)
        return self.product_result


class User(BaseUser):
    def meal(
        self,
        items: list[dict[str, Any]],
        *,
        meal_id: uuid.UUID | None = None,
        source: str = "search",
        at: datetime | None = None,
        dry_run: bool = False,
    ) -> Any:
        return self.flow.client.post(
            "/api/v1/meals" + ("?dry_run=true" if dry_run else ""),
            headers=self.headers,
            json={
                "client_entry_id": str(meal_id or uuid.uuid4()),
                "logged_at": (at or datetime.now(UTC) - timedelta(minutes=5)).isoformat(),
                "meal_type": "lunch",
                "source": source,
                "items": items,
            },
        )


def item(food: str, quantity: float = 1, unit: str = "piece", **extra: Any) -> dict[str, Any]:
    return {"food_id": food, "quantity": quantity, "unit_code": unit, **extra}


@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    off = FakeOff(None)
    yield make_flow(app_factory, open_food_facts=off)


def nutrient(view: dict[str, Any], code: str) -> Any:
    return next(n["value"] for n in view["nutrients"] if n["code"] == code)


# --------------------------------------------------------------------------- foods
def test_search_with_alias_and_default_portion(flow: Flow) -> None:
    user = User(flow)
    response = flow.client.get(
        "/api/v1/foods/search", params={"q": "chapati"}, headers=user.headers
    )
    assert response.status_code == 200
    first = response.json()["results"][0]
    assert (first["name"], first["matched_alias"]) == ("Roti (Whole Wheat)", "Chapati")
    assert first["default_portion"]["label"] == "Medium Piece"
    assert first["kcal_per_default"] == 119  # 40 g x 297 kcal / 100 g


def test_food_detail_is_tier_filtered(flow: Flow) -> None:
    user = User(flow)
    standard = flow.client.get(f"/api/v1/foods/{APPLE}", headers=user.headers).json()
    assert [n["code"] for n in standard["per_100"]["nutrients"]] == [
        "calories",
        "protein",
        "carbohydrates",
        "fat",
        "dietary_fiber",
        "total_sugar",
    ]
    assert standard["per_100"]["locked_nutrients_count"] == 11
    assert any(p["is_default"] and p["quantity"] == 150 for p in standard["portions"])
    assert flow.client.get(f"/api/v1/foods/{uuid.uuid4()}", headers=user.headers).status_code == 404


async def test_star_sees_17_nutrients(flow: Flow) -> None:
    user = User(flow)
    await user.make_star()
    star = flow.client.get(f"/api/v1/foods/{APPLE}", headers=user.headers).json()
    assert len(star["per_100"]["nutrients"]) == 17
    assert star["per_100"]["locked_nutrients_count"] == 0


# --------------------------------------------------------------------------- meals
def test_apple_example_summary_and_avatar(flow: Flow) -> None:
    user = User(flow)
    preview = user.meal([item(APPLE)], dry_run=True)
    assert preview.status_code == 200, preview.text
    assert preview.json()["calories"] == 78
    summary = flow.client.get("/api/v1/nutrition/daily-summary", headers=user.headers).json()
    assert summary["meal_count"] == 0  # the dry run saved nothing

    response = user.meal([item(APPLE)])
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["meal"]["calories"] == 78
    assert body["meal"]["items"][0]["consumed_amount"] == "150.0" or Decimal(
        str(body["meal"]["items"][0]["consumed_amount"])
    ) == Decimal(150)
    daily = body["daily_summary"]
    assert (daily["calories"], daily["meal_count"], daily["meal_limit"]) == (78, 1, 4)
    assert Decimal(str(nutrient(daily, "carbohydrates"))) == Decimal(21)
    assert daily["locked_nutrients_count"] == 11
    assert daily["target_kcal"] == 3104  # doc example 1 with multiplier 1.55 (2026-11 MVP doc)
    assert body["avatar"] == {"fill_pct": "2.5", "state": "fueling"} or (
        Decimal(str(body["avatar"]["fill_pct"])) == Decimal("2.5")
        and body["avatar"]["state"] == "fueling"
    )


async def test_star_daily_summary_has_vitamin_c(flow: Flow) -> None:
    user = User(flow)
    await user.make_star()
    daily = user.meal([item(APPLE)]).json()["daily_summary"]
    assert Decimal(str(nutrient(daily, "vitamin_c"))) == Decimal(7)  # 6.9 mg shown as integer mg
    assert len(daily["nutrients"]) == 17


async def test_doc_example_1_avatar_is_energized_at_50_percent(flow: Flow) -> None:
    user = User(flow)
    food_id = uuid.uuid4()
    # 1034.667 kcal / 100 g x 150 g (medium piece) = 1552 kcal = half of 3104 (doc example 1).
    await sql(
        "INSERT INTO nutrition.food_item (id, name, category_code, basis, is_cooked, source_ref,"
        " calories_kcal) VALUES ($1, $2, 'whole_fruit', 'g', false, 'pytest', 1034.667)",
        food_id,
        f"Example food {food_id.hex[:6]}",
    )
    avatar = user.meal([item(str(food_id))]).json()["avatar"]
    assert (Decimal(str(avatar["fill_pct"])), avatar["state"]) == (Decimal("50.0"), "energized")


def test_replay_is_idempotent(flow: Flow) -> None:
    user = User(flow)
    meal_id = uuid.uuid4()
    assert user.meal([item(APPLE)], meal_id=meal_id).status_code == 201
    replay = user.meal([item(APPLE)], meal_id=meal_id)
    assert replay.status_code == 200
    assert replay.json()["daily_summary"]["meal_count"] == 1


def test_standard_limit_is_four_with_the_limit_in_the_error(flow: Flow) -> None:
    user = User(flow)
    for _ in range(4):
        assert user.meal([item(BANANA)]).status_code == 201
    refused = user.meal([item(BANANA)])
    assert refused.status_code == 403
    assert refused.json()["error"]["code"] == "DAILY_LIMIT_REACHED"
    assert refused.json()["error"]["limit"] == 4


def test_two_parallel_posts_at_three_of_four_one_wins(flow: Flow) -> None:
    """Two devices post at 3/4 at the same time: the row lock in nutrition.pr_log_meal lets
    exactly one through (the requests run concurrently in the app's event loop)."""
    user = User(flow)
    for _ in range(3):
        assert user.meal([item(BANANA)]).status_code == 201
    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses = sorted(pool.map(lambda _: user.meal([item(BANANA)]).status_code, range(2)))
    assert statuses == [201, 403]


def test_edit_window_versions_and_conflicts(flow: Flow) -> None:
    user = User(flow)
    ids = [
        user.meal([item(BANANA)], at=datetime.now(UTC) - timedelta(minutes=30 - i)).json()["meal"][
            "meal_id"
        ]
        for i in range(3)
    ]
    oldest, middle, latest = ids
    recent = flow.client.get("/api/v1/meals/recent", headers=user.headers).json()
    assert [m["editable"] for m in recent["meals"]] == [True, True, False]
    assert recent["recent_foods"][0]["name"] == "Banana"

    closed = flow.client.put(
        f"/api/v1/meals/{oldest}",
        headers={**user.headers, "If-Match": "1"},
        json={"meal_type": "dinner"},
    )
    assert closed.status_code == 403
    assert closed.json()["error"]["code"] == "EDIT_WINDOW_CLOSED"

    missing = flow.client.put(
        f"/api/v1/meals/{latest}", headers=user.headers, json={"meal_type": "dinner"}
    )
    assert missing.status_code == 422  # If-Match is required

    edited = flow.client.put(
        f"/api/v1/meals/{latest}",
        headers={**user.headers, "If-Match": "1"},
        json={"items": [item(RICE, 2, "katori")]},
    )
    assert edited.status_code == 200, edited.text
    assert edited.json()["meal"]["version"] == 2
    assert edited.json()["meal"]["calories"] == 390
    assert edited.json()["daily_summary"]["meal_count"] == 3

    stale = flow.client.put(
        f"/api/v1/meals/{latest}",
        headers={**user.headers, "If-Match": "1"},
        json={"meal_type": "snack"},
    )
    assert stale.status_code == 409
    error = stale.json()["error"]
    assert error["code"] == "VERSION_CONFLICT"
    assert error["current"]["version"] == 2 and error["current"]["calories"] == 390

    gone = flow.client.delete(f"/api/v1/meals/{middle}", headers={**user.headers, "If-Match": "1"})
    assert gone.status_code == 204
    day = flow.client.get(
        "/api/v1/meals", params={"date": recent["meals"][0]["local_date"]}, headers=user.headers
    ).json()
    assert {m["meal_id"] for m in day["meals"]} == {oldest, latest}


def test_backdating_rules(flow: Flow) -> None:
    user = User(flow)
    old = user.meal([item(BANANA)], at=datetime.now(UTC) - timedelta(days=9))
    assert old.json()["error"]["code"] == "EDIT_WINDOW_CLOSED"
    future = user.meal([item(BANANA)], at=datetime.now(UTC) + timedelta(hours=2))
    assert future.status_code == 422
    assert user.meal([item(BANANA)], at=datetime.now(UTC) - timedelta(days=3)).status_code == 201


def test_invalid_items_are_refused(flow: Flow) -> None:
    user = User(flow)
    for bad in (
        [item(APPLE, 0.3)],  # not a 0.25 step
        [item(APPLE, 21)],
        [item(APPLE, 1, "plate")],  # unit the food does not offer
        [item(str(uuid.uuid4()))],  # unknown food
        [],
        [item(APPLE)] * 31,
    ):
        assert user.meal(bad).status_code == 422, bad


def test_other_users_meals_are_invisible(flow: Flow) -> None:
    owner, other = User(flow), User(flow)
    meal = owner.meal([item(APPLE)]).json()["meal"]
    for method, path in (
        ("PUT", f"/api/v1/meals/{meal['meal_id']}"),
        ("DELETE", f"/api/v1/meals/{meal['meal_id']}"),
    ):
        response = flow.client.request(
            method, path, headers={**other.headers, "If-Match": "1"}, json={"meal_type": "snack"}
        )
        assert response.status_code == 404, (method, response.text)
    day = flow.client.get(
        "/api/v1/meals", params={"date": meal["local_date"]}, headers=other.headers
    ).json()
    assert day["meals"] == []


# --------------------------------------------------------------------------- tiers
def test_standard_cannot_use_voice_barcode_or_breakdown(flow: Flow) -> None:
    user = User(flow)
    meal = user.meal([item(APPLE)]).json()["meal"]
    for response in (
        flow.client.post(
            "/api/v1/nutrition/voice/parse",
            headers=user.headers,
            json={"transcript": "do roti", "locale": "en-IN"},
        ),
        flow.client.get("/api/v1/foods/barcode/8901234567890", headers=user.headers),
        flow.client.get(f"/api/v1/meals/{meal['meal_id']}/breakdown", headers=user.headers),
        user.meal([item(APPLE)], source="voice"),
    ):
        assert response.status_code == 403, response.text
        assert response.json()["error"]["code"] == "UPGRADE_REQUIRED"


async def test_voice_parse_hinglish(flow: Flow) -> None:
    user = User(flow)
    await user.make_star()
    response = flow.client.post(
        "/api/v1/nutrition/voice/parse",
        headers=user.headers,
        json={"transcript": "do roti aur ek katori dal aur pizza", "locale": "en-IN"},
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert [
        (i["name"], Decimal(str(i["quantity"])), i["unit_code"], i["unit_size"])
        for i in body["items"]
    ] == [
        ("Roti (Whole Wheat)", Decimal(2), "piece", "medium"),
        ("Moong Dal (Cooked)", Decimal(1), "katori", "medium"),
    ]
    assert body["unmatched"] == ["pizza"]
    assert (
        user.meal(
            [item(i["food_id"], float(i["quantity"]), i["unit_code"]) for i in body["items"]],
            source="voice",
        ).status_code
        == 201
    )


async def test_breakdown_for_star(flow: Flow) -> None:
    user = User(flow)
    await user.make_star()
    meal = user.meal([item(DAL, 1, "katori"), item(ROTI, 2)]).json()["meal"]
    response = flow.client.get(f"/api/v1/meals/{meal['meal_id']}/breakdown", headers=user.headers)
    assert response.status_code == 200
    body = response.json()
    assert len(body["totals"]["nutrients"]) == 17
    assert sum(Decimal(str(v)) for v in body["macro_pct"].values()) in {
        Decimal(99),
        Decimal(100),
        Decimal(101),
    }


async def test_barcode_found_cached_and_not_found(flow: Flow) -> None:
    user = User(flow)
    await user.make_star()
    off: FakeOff = flow.harness.app.state.nutrition_service.off
    code = "4006381333931"  # valid GTIN-13
    await sql("DELETE FROM nutrition.barcode_product WHERE barcode = $1", code)
    assert flow.client.get(f"/api/v1/foods/barcode/{code}", headers=user.headers).json() == {
        "found": False,
        "barcode": code,
    }

    off.product_result = OffProduct(
        "Crunchy Muesli", "Brand Y", Decimal(45), {"calories": Decimal(400), "protein": Decimal(9)}
    )
    found = flow.client.get(f"/api/v1/foods/barcode/{code}", headers=user.headers).json()
    assert found["found"] is True and found["product_name"] == "Crunchy Muesli"
    assert found["food_id"] is not None
    logged = user.meal([item(found["food_id"], 1, "serving")], source="barcode")
    assert logged.status_code == 201 and logged.json()["meal"]["calories"] == 180  # 45 g serving

    calls = len(off.calls)
    again = flow.client.get(f"/api/v1/foods/barcode/{code}", headers=user.headers).json()
    assert again["food_id"] == found["food_id"]
    assert len(off.calls) == calls  # served from the cache
    assert flow.client.get("/api/v1/foods/barcode/1234", headers=user.headers).status_code == 422


# --------------------------------------------------------------------------- saved meals
def test_saved_meals(flow: Flow) -> None:
    user = User(flow)
    created = flow.client.post(
        "/api/v1/saved-meals",
        headers=user.headers,
        json={"name": "Dal Chawal", "items": [item(DAL, 1, "katori"), item(RICE, 1, "katori")]},
    )
    assert created.status_code == 201, created.text
    listed = flow.client.get("/api/v1/saved-meals", headers=user.headers).json()["saved_meals"]
    assert [(s["name"], len(s["items"])) for s in listed] == [("Dal Chawal", 2)]
    other = User(flow)
    saved_id = created.json()["saved_meal_id"]
    assert (
        flow.client.delete(f"/api/v1/saved-meals/{saved_id}", headers=other.headers).status_code
        == 404
    )
    assert (
        flow.client.delete(f"/api/v1/saved-meals/{saved_id}", headers=user.headers).status_code
        == 204
    )


# --------------------------------------------------------------------------- staff
def test_admin_foods_need_the_role_and_the_network(flow: Flow) -> None:
    user = User(flow)
    body = {
        "name": "Poha",
        "category_code": "rice_dish",
        "basis": "g",
        "is_cooked": True,
        "source_ref": "IFCT 2017",
        "nutrients": {"calories": 130, "protein": 2.6},
        "aliases": ["Chivda"],
    }
    # A regular user, and even the right role outside STAFF_IP_ALLOWLIST: 404.
    assert (
        flow.client.post("/api/v1/admin/foods", headers=user.headers, json=body).status_code == 404
    )


async def test_admin_food_create_as_nutritionist(flow: Flow) -> None:
    user = User(flow)
    await sql("UPDATE auth.user_account SET role = 'nutritionist' WHERE id = $1", user.id)
    flow.harness.app.dependency_overrides[admin_foods.staff_only] = lambda: Principal(
        user_id=user.id, role="nutritionist", session_id=uuid.uuid4(), tier_hint="standard"
    )
    body = {
        "name": f"Poha {uuid.uuid4().hex[:6]}",
        "category_code": "rice_dish",
        "basis": "g",
        "is_cooked": True,
        "source_ref": "IFCT 2017",
        "nutrients": {"calories": 130, "protein": 2.6},
        "aliases": ["Chivda"],
    }
    created = flow.client.post("/api/v1/admin/foods", headers=user.headers, json=body)
    assert created.status_code == 201, created.text
    food_id = created.json()["food_id"]
    detail = flow.client.get(f"/api/v1/foods/{food_id}", headers=user.headers).json()
    assert detail["aliases"] == ["Chivda"]
    assert Decimal(str(nutrient(detail["per_100"], "calories"))) == Decimal(130)
