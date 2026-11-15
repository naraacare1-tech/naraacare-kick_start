"""Open Food Facts product lookup, the barcode fallback (OQ-44; data under ODbL, credited on the
Licenses screen).

Security (doc 07, OWASP API10 "unsafe consumption of APIs", SSRF):
* The URL is the configured base URL + a fixed path + the barcode, which has already passed
  ``SafeBarcode`` (8-14 digits with a valid GTIN check digit). No user-supplied URL or host.
* 3 s timeout, no redirects (the shared client has ``follow_redirects=False``), body capped at
  256 KiB, JSON only, a fixed ``fields`` list.
* Every value is validated before it is stored: the product name must pass ``SafeShortText``
  (else "Unnamed product"), numbers must be finite and inside the column ranges (else dropped).
* Failures (timeout, HTTP error, bad JSON) return ``None``: the app falls back to manual search.
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, field
from decimal import Decimal, InvalidOperation
from http import HTTPStatus
from typing import Any

import httpx2
import structlog

from app.core.security.validators import Kind, SafeString

log = structlog.get_logger(__name__)

TIMEOUT_S = 3.0
MAX_BODY_BYTES = 256 * 1024
UNNAMED = "Unnamed product"
_NAME = SafeString(Kind.SHORT_TEXT, 120)
_BRAND = SafeString(Kind.SHORT_TEXT, 80)
FIELDS = "product_name,brands,serving_quantity,nutriments"

# OFF nutriment key (per 100 g, in g unless noted) -> (our nutrient code, factor to our unit, max).
_NUTRIMENTS: dict[str, tuple[str, Decimal, Decimal]] = {
    "energy-kcal_100g": ("calories", Decimal(1), Decimal(900)),
    "proteins_100g": ("protein", Decimal(1), Decimal(100)),
    "carbohydrates_100g": ("carbohydrates", Decimal(1), Decimal(100)),
    "fat_100g": ("fat", Decimal(1), Decimal(100)),
    "fiber_100g": ("dietary_fiber", Decimal(1), Decimal(100)),
    "sugars_100g": ("total_sugar", Decimal(1), Decimal(100)),
    "saturated-fat_100g": ("saturated_fat", Decimal(1), Decimal(100)),
    "polyunsaturated-fat_100g": ("polyunsaturated_fat", Decimal(1), Decimal(100)),
    "monounsaturated-fat_100g": ("monounsaturated_fat", Decimal(1), Decimal(100)),
    "trans-fat_100g": ("trans_fat", Decimal(1), Decimal(100)),
    "cholesterol_100g": ("cholesterol", Decimal(1000), Decimal(100000)),  # g -> mg
    "sodium_100g": ("sodium", Decimal(1000), Decimal(100000)),
    "potassium_100g": ("potassium", Decimal(1000), Decimal(100000)),
    "calcium_100g": ("calcium", Decimal(1000), Decimal(100000)),
    "iron_100g": ("iron", Decimal(1000), Decimal(100000)),
    "vitamin-a_100g": ("vitamin_a", Decimal(1_000_000), Decimal(100000)),  # g -> mcg
    "vitamin-c_100g": ("vitamin_c", Decimal(1000), Decimal(100000)),
}


@dataclass(frozen=True, slots=True)
class OffProduct:
    product_name: str
    brand: str | None
    serving_g: Decimal | None
    nutrients: dict[str, Decimal] = field(default_factory=dict)


def _number(value: object, factor: Decimal, maximum: Decimal) -> Decimal | None:
    if isinstance(value, bool) or not isinstance(value, int | float | str):
        return None
    try:
        number = Decimal(str(value))
    except InvalidOperation:
        return None
    if not number.is_finite() or (isinstance(value, float) and not math.isfinite(value)):
        return None
    scaled = (number * factor).quantize(Decimal("0.001"))
    return scaled if Decimal(0) <= scaled <= maximum else None


def _text(validator: SafeString, value: object) -> str | None:
    if not isinstance(value, str) or not value.strip():
        return None
    try:
        return validator.validate(value.strip()[: validator.max_length])
    except ValueError:  # PydanticCustomError is a ValueError
        return None


def parse_product(data: dict[str, Any]) -> OffProduct | None:
    """A validated product from an OFF v2 response, or None when it reports no product."""
    if data.get("status") != 1 or not isinstance(data.get("product"), dict):
        return None
    product: dict[str, Any] = data["product"]
    nutriments = product.get("nutriments")
    nutrients: dict[str, Decimal] = {}
    if isinstance(nutriments, dict):
        for key, (code, factor, maximum) in _NUTRIMENTS.items():
            value = _number(nutriments.get(key), factor, maximum)
            if value is not None:
                nutrients[code] = value
    brands = product.get("brands")
    first_brand = brands.split(",")[0] if isinstance(brands, str) else None
    serving = _number(product.get("serving_quantity"), Decimal(1), Decimal(2000))
    return OffProduct(
        product_name=_text(_NAME, product.get("product_name")) or UNNAMED,
        brand=_text(_BRAND, first_brand),
        serving_g=serving if serving and serving > 0 else None,
        nutrients=nutrients,
    )


class OpenFoodFacts:
    def __init__(self, http: httpx2.AsyncClient, base_url: str, user_agent: str) -> None:
        self._http = http
        self._base = base_url.rstrip("/")
        self._user_agent = user_agent

    async def product(self, barcode: str) -> OffProduct | None:
        """``barcode`` must already be a validated ``SafeBarcode`` (digits only)."""
        if not barcode.isdigit():
            return None
        url = f"{self._base}/api/v2/product/{barcode}.json"
        try:
            async with self._http.stream(
                "GET",
                url,
                params={"fields": FIELDS},
                headers={"User-Agent": self._user_agent, "Accept": "application/json"},
                timeout=TIMEOUT_S,
            ) as response:
                if response.status_code == HTTPStatus.NOT_FOUND:
                    return None
                response.raise_for_status()
                body = bytearray()
                async for chunk in response.aiter_bytes():
                    body.extend(chunk)
                    if len(body) > MAX_BODY_BYTES:
                        log.warning("off_response_too_large")
                        return None
            data = json.loads(bytes(body))
        except (httpx2.HTTPError, ValueError) as exc:
            log.warning("off_lookup_failed", exc_type=type(exc).__name__)
            return None
        return parse_product(data) if isinstance(data, dict) else None
