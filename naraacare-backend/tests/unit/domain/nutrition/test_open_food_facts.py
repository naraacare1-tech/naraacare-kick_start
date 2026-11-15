"""Open Food Facts fallback (OQ-44): fixed URL, validated values, failures are not errors."""

from __future__ import annotations

import json
from decimal import Decimal
from typing import Any

import httpx2
import pytest

from app.integrations.open_food_facts import (
    MAX_BODY_BYTES,
    UNNAMED,
    OpenFoodFacts,
    parse_product,
)

PRODUCT: dict[str, Any] = {
    "status": 1,
    "product": {
        "product_name": "Masala Oats",
        "brands": "Brand X, Parent Co",
        "serving_quantity": 38,
        "nutriments": {
            "energy-kcal_100g": 380,
            "proteins_100g": "12.5",
            "carbohydrates_100g": 64,
            "fat_100g": 8,
            "sodium_100g": 0.6,  # g -> 600 mg
            "vitamin-a_100g": 0.0003,  # g -> 300 mcg
            "iron_100g": float("nan"),
            "sugars_100g": -3,
            "fiber_100g": True,
        },
    },
}


def test_parse_converts_units_and_drops_invalid_numbers() -> None:
    product = parse_product(PRODUCT)
    assert product is not None
    assert product.product_name == "Masala Oats"
    assert product.brand == "Brand X"
    assert product.serving_g == Decimal("38.000")
    assert product.nutrients == {
        "calories": Decimal("380.000"),
        "protein": Decimal("12.500"),
        "carbohydrates": Decimal("64.000"),
        "fat": Decimal("8.000"),
        "sodium": Decimal("600.000"),
        "vitamin_a": Decimal("300.000"),
    }


@pytest.mark.parametrize(
    "name", ["<script>alert(1)</script>", "Oats {{7*7}}", "javascript:alert(1)", "", None, 42]
)
def test_unsafe_or_missing_names_become_unnamed(name: object) -> None:
    data = {"status": 1, "product": {**PRODUCT["product"], "product_name": name, "brands": name}}
    product = parse_product(data)
    assert product is not None
    assert product.product_name == UNNAMED
    assert product.brand is None


def test_no_product() -> None:
    assert parse_product({"status": 0}) is None
    assert parse_product({"status": 1, "product": "x"}) is None


def client(handler: Any) -> OpenFoodFacts:
    http = httpx2.AsyncClient(transport=httpx2.MockTransport(handler), follow_redirects=False)
    return OpenFoodFacts(http, "https://off.example/", "NaraaCare-test")


async def test_requests_the_fixed_url_with_a_user_agent() -> None:
    seen: list[httpx2.Request] = []

    clean = {"status": 1, "product": {**PRODUCT["product"], "nutriments": {"fat_100g": 8}}}

    def handler(request: httpx2.Request) -> httpx2.Response:
        seen.append(request)
        return httpx2.Response(200, json=clean)

    product = await client(handler).product("8901234567890")
    assert product is not None and product.product_name == "Masala Oats"
    (request,) = seen
    assert str(request.url).startswith("https://off.example/api/v2/product/8901234567890.json?")
    assert request.headers["User-Agent"] == "NaraaCare-test"


async def test_non_digit_codes_are_never_sent() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:  # pragma: no cover - must not run
        raise AssertionError("no request expected")

    assert await client(handler).product("../admin") is None


@pytest.mark.parametrize(
    "response",
    [
        httpx2.Response(404),
        httpx2.Response(500),
        httpx2.Response(302, headers={"Location": "https://elsewhere.example/"}),
        httpx2.Response(200, content=b"not json"),
        httpx2.Response(200, content=b"x" * (MAX_BODY_BYTES + 10)),
        httpx2.Response(200, content=json.dumps([1, 2]).encode()),
    ],
)
async def test_failures_return_none(response: httpx2.Response) -> None:
    assert await client(lambda _: response).product("8901234567890") is None


async def test_timeouts_return_none() -> None:
    def handler(request: httpx2.Request) -> httpx2.Response:
        raise httpx2.ReadTimeout("slow", request=request)

    assert await client(handler).product("8901234567890") is None
