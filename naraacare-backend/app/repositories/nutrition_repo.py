"""Nutrition: foods, meals, summaries, saved meals, barcodes and the nutritionist food upsert
(doc 04 section 2.4). Stored routine calls only; all nutrient maths happens in the database."""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

SEARCH_FOODS = db_call("SELECT * FROM nutrition.fn_search_foods(:query, :limit)")
FOOD_DETAIL = db_call("SELECT * FROM nutrition.fn_food_detail(:food_id)")
FOOD_PORTIONS = db_call("SELECT * FROM nutrition.fn_food_portions(:food_ids)")
BARCODE_LOOKUP = db_call("SELECT * FROM nutrition.fn_barcode_lookup(:barcode)")
ALIAS_MATCH = db_call("SELECT * FROM nutrition.fn_alias_match(:phrases)")
PREVIEW_MEAL = db_call("SELECT * FROM nutrition.fn_preview_meal(:user_id, :items)")
LOG_MEAL = db_call(
    "CALL nutrition.pr_log_meal(:user_id, :meal_id, :logged_at, :meal_type, :source, :items, "
    "NULL, NULL)"
)
UPDATE_MEAL = db_call(
    "CALL nutrition.pr_update_meal(:user_id, :meal_id, :version, :meal_type, :items, NULL)"
)
DELETE_MEAL = db_call("CALL nutrition.pr_delete_meal(:user_id, :meal_id, :version)")
MEALS_BY_DATE = db_call("SELECT * FROM nutrition.fn_meals_by_date(:user_id, :on_date)")
RECENT_MEALS = db_call("SELECT * FROM nutrition.fn_recent_meals(:user_id, :limit)")
RECENT_FOODS = db_call("SELECT * FROM nutrition.fn_recent_foods(:user_id, :limit)")
MEAL_BREAKDOWN = db_call("SELECT * FROM nutrition.fn_meal_breakdown(:user_id, :meal_id)")
DAILY_SUMMARY = db_call("SELECT * FROM nutrition.fn_daily_summary(:user_id, :on_date)")
SAVED_MEALS = db_call("SELECT * FROM nutrition.fn_saved_meals(:user_id)")
SAVE_MEAL_TEMPLATE = db_call("CALL nutrition.pr_save_meal_template(:user_id, :name, :items, NULL)")
DELETE_SAVED_MEAL = db_call("CALL nutrition.pr_delete_saved_meal(:user_id, :saved_meal_id)")
UPSERT_BARCODE = db_call(
    "CALL nutrition.pr_upsert_barcode_product(:user_id, :barcode, :product_name, :brand, "
    ":serving_g, :nutrients, NULL)"
)
ADMIN_UPSERT_FOOD = db_call(
    "CALL nutrition.pr_admin_upsert_food(:user_id, :food_id, :name, :category_code, :basis, "
    ":density, :is_cooked, :source_ref, :nutrients, :aliases, :alias_language, NULL)"
)


def _json(value: object) -> str:
    return json.dumps(value, default=str)


def items_json(items: Sequence[Mapping[str, Any]]) -> str:
    """Meal items as the procedures expect them; quantities stay JSON numbers."""
    return json.dumps(
        [
            {
                "food_id": str(i["food_id"]),
                "quantity": float(i["quantity"])
                if isinstance(i["quantity"], Decimal)
                else i["quantity"],
                "unit_code": i["unit_code"],
                **({"unit_size": i["unit_size"]} if i.get("unit_size") else {}),
            }
            for i in items
        ]
    )


async def search_foods(session: DbSession, query: str, limit: int) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(SEARCH_FOODS, query=query, limit=limit)


async def food_detail(session: DbSession, food_id: UUID) -> Mapping[str, Any] | None:
    return await session.fetch_one(FOOD_DETAIL, food_id=food_id)


async def food_portions(session: DbSession, food_ids: list[UUID]) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(FOOD_PORTIONS, food_ids=food_ids)


async def barcode_lookup(session: DbSession, barcode: str) -> Mapping[str, Any] | None:
    return await session.fetch_one(BARCODE_LOOKUP, barcode=barcode)


async def alias_match(session: DbSession, phrases: list[str]) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(ALIAS_MATCH, phrases=phrases)


async def preview_meal(
    session: DbSession, user_id: UUID, items: Sequence[Mapping[str, Any]]
) -> Mapping[str, Any] | None:
    return await session.fetch_one(PREVIEW_MEAL, user_id=user_id, items=items_json(items))


async def log_meal(
    session: DbSession,
    user_id: UUID,
    *,
    meal_id: UUID,
    logged_at: datetime,
    meal_type: str,
    source: str,
    items: Sequence[Mapping[str, Any]],
) -> tuple[str, date]:
    row = await session.fetch_one(
        LOG_MEAL,
        user_id=user_id,
        meal_id=meal_id,
        logged_at=logged_at,
        meal_type=meal_type,
        source=source,
        items=items_json(items),
    )
    row = row or {}
    return str(row["o_status"]), row["o_local_date"]


async def update_meal(
    session: DbSession,
    user_id: UUID,
    meal_id: UUID,
    *,
    version: int,
    meal_type: str | None,
    items: Sequence[Mapping[str, Any]] | None,
) -> int:
    row = await session.fetch_one(
        UPDATE_MEAL,
        user_id=user_id,
        meal_id=meal_id,
        version=version,
        meal_type=meal_type,
        items=items_json(items) if items is not None else None,
    )
    return int((row or {})["o_version"])


async def delete_meal(session: DbSession, user_id: UUID, meal_id: UUID, version: int) -> None:
    await session.execute(DELETE_MEAL, user_id=user_id, meal_id=meal_id, version=version)


async def meals_by_date(
    session: DbSession, user_id: UUID, on_date: date
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(MEALS_BY_DATE, user_id=user_id, on_date=on_date)


async def recent_meals(
    session: DbSession, user_id: UUID, limit: int
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(RECENT_MEALS, user_id=user_id, limit=limit)


async def recent_foods(
    session: DbSession, user_id: UUID, limit: int
) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(RECENT_FOODS, user_id=user_id, limit=limit)


async def meal_breakdown(
    session: DbSession, user_id: UUID, meal_id: UUID
) -> Mapping[str, Any] | None:
    return await session.fetch_one(MEAL_BREAKDOWN, user_id=user_id, meal_id=meal_id)


async def daily_summary(
    session: DbSession, user_id: UUID, on_date: date | None
) -> Mapping[str, Any] | None:
    return await session.fetch_one(DAILY_SUMMARY, user_id=user_id, on_date=on_date)


async def saved_meals(session: DbSession, user_id: UUID) -> Sequence[Mapping[str, Any]]:
    return await session.fetch_all(SAVED_MEALS, user_id=user_id)


async def save_meal_template(
    session: DbSession, user_id: UUID, name: str, items: Sequence[Mapping[str, Any]]
) -> UUID:
    row = await session.fetch_one(
        SAVE_MEAL_TEMPLATE, user_id=user_id, name=name, items=items_json(items)
    )
    return UUID(str((row or {})["o_saved_meal_id"]))


async def delete_saved_meal(session: DbSession, user_id: UUID, saved_meal_id: UUID) -> None:
    await session.execute(DELETE_SAVED_MEAL, user_id=user_id, saved_meal_id=saved_meal_id)


async def upsert_barcode_product(
    session: DbSession,
    user_id: UUID,
    *,
    barcode: str,
    product_name: str,
    brand: str | None,
    serving_g: Decimal | None,
    nutrients: Mapping[str, Decimal],
) -> UUID | None:
    row = await session.fetch_one(
        UPSERT_BARCODE,
        user_id=user_id,
        barcode=barcode,
        product_name=product_name,
        brand=brand,
        serving_g=serving_g,
        nutrients=_json({k: float(v) for k, v in nutrients.items()}),
    )
    food_id = (row or {}).get("o_food_id")
    return UUID(str(food_id)) if food_id else None


async def admin_upsert_food(
    session: DbSession, user_id: UUID, food_id: UUID | None, fields: Mapping[str, Any]
) -> UUID:
    row = await session.fetch_one(
        ADMIN_UPSERT_FOOD,
        user_id=user_id,
        food_id=food_id,
        name=fields["name"],
        category_code=fields["category_code"],
        basis=fields["basis"],
        density=fields.get("density_g_per_ml"),
        is_cooked=fields["is_cooked"],
        source_ref=fields["source_ref"],
        nutrients=_json({k: float(v) for k, v in fields["nutrients"].items() if v is not None}),
        aliases=_json(list(fields["aliases"])) if fields.get("aliases") is not None else None,
        alias_language=fields.get("alias_language", "hinglish"),
    )
    return UUID(str((row or {})["o_food_id"]))
