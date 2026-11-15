"""Nutrition tracking (doc 04 section 2.4, doc 06 sections 2.8-2.11, Session 08).

* All nutrient maths happens in the database (``nutrition.fn_item_nutrients``); this layer filters
  by tier, rounds for display and computes the avatar state from the server totals.
* Tier rules (doc 04 section 3): STANDARD sees 6 nutrients + ``locked_nutrients_count``; voice,
  barcode and the meal breakdown are STAR (403 UPGRADE_REQUIRED with ``feature``). The database
  enforces the meal limit and the voice/barcode source again under its own lock.
* Errors are enriched with safe details: ``limit`` on DAILY_LIMIT_REACHED and the server copy of
  the meal as ``current`` on 409 VERSION_CONFLICT (doc 04, the app's conflict resolver).
"""

from __future__ import annotations

import json
from collections.abc import Mapping, Sequence
from datetime import date, datetime
from decimal import Decimal
from typing import Any
from uuid import UUID

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain.entitlements.service import Entitlement, EntitlementService
from app.domain.nutrition import nutrients as nutrient_rules
from app.domain.nutrition.avatar import avatar_state
from app.domain.nutrition.nutrients import Nutrient, display_value, visible
from app.domain.nutrition.voice_parser import parse_transcript
from app.domain.reference import ReferenceCache
from app.integrations.open_food_facts import OpenFoodFacts
from app.repositories import nutrition_repo
from app.repositories.base import Database, DbSession

MACRO_KCAL_PER_G = {"carbohydrates": Decimal(4), "protein": Decimal(4), "fat": Decimal(9)}
VOICE_MIN_CONFIDENCE = Decimal("0.35")


def _obj(value: object) -> Any:
    return json.loads(value) if isinstance(value, str | bytes) else value


def _int(value: object) -> int:
    return int(display_value("kcal", Decimal(str(value or 0))) or 0)


class NutritionService:
    def __init__(
        self,
        *,
        db: Database,
        reference: ReferenceCache,
        entitlements: EntitlementService,
        open_food_facts: OpenFoodFacts,
    ) -> None:
        self.db = db
        self.reference = reference
        self.entitlements = entitlements
        self.off = open_food_facts

    # ------------------------------------------------------------------ helpers
    async def _nutrients(self) -> tuple[Nutrient, ...]:
        return nutrient_rules.nutrients_from_bootstrap((await self.reference.bootstrap()).payload)

    async def _require(self, principal: Principal, feature: str) -> Entitlement:
        entitlement = await self.entitlements.get(principal.user_id)
        if not entitlement.allows(feature):
            raise AppError(ErrorCode.UPGRADE_REQUIRED, extra={"feature": feature})
        return entitlement

    async def _view(self, tier: str, raw: Mapping[str, Any] | None) -> dict[str, Any]:
        view = visible(await self._nutrients(), tier, raw)
        return {"nutrients": view.values, "locked_nutrients_count": view.locked_nutrients_count}

    @staticmethod
    def meal_out(row: Mapping[str, Any]) -> dict[str, Any]:
        """A meal for lists: kcal per item and in total (the full nutrients are the STAR
        breakdown)."""
        totals = _obj(row["totals"]) or {}
        return {
            "meal_id": str(row["meal_id"]),
            "logged_at": row["logged_at"].isoformat(),
            "local_date": row["local_date"].isoformat(),
            "meal_type": row["meal_type"],
            "source": row["source"],
            "version": row["version"],
            "editable": bool(row["editable"]),
            "hydration_credit": bool(row["hydration_credit"]),
            "calories": _int(totals.get("calories")),
            "items": [
                {
                    "item_id": str(i["item_id"]),
                    "food_id": str(i["food_id"]),
                    "food_name": i["food_name"],
                    "quantity": Decimal(str(i["quantity"])),
                    "unit_code": i["unit_code"],
                    "unit_size": i["unit_size"],
                    "consumed_amount": Decimal(str(i["consumed_amount"])),
                    "consumed_basis": i["consumed_basis"],
                    "calories": _int(i["nutrients"]["calories"]),
                }
                for i in _obj(row["items"]) or []
            ],
        }

    async def _summary_out(self, tier: str, row: Mapping[str, Any]) -> dict[str, Any]:
        totals = _obj(row["totals"]) or {}
        allowance = row["effective_allowance_kcal"]
        avatar = avatar_state(Decimal(str(totals.get("calories", 0))), allowance)
        last = row.get("last_updated")
        return {
            "date": row["local_date"].isoformat(),
            "calories": _int(totals.get("calories")),
            **await self._view(tier, totals),
            "target_kcal": row["base_target_kcal"],
            "effective_allowance_kcal": allowance,
            "exercise_kcal": row["exercise_kcal"],
            "avatar": {"fill_pct": avatar.fill_pct, "state": avatar.state},
            "meal_count": row["meal_count"],
            "meal_limit": row["meal_limit"],
            "last_updated": last.isoformat() if isinstance(last, datetime) else None,
        }

    # ------------------------------------------------------------------ foods
    async def search(self, principal: Principal, query: str, limit: int) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: nutrition_repo.search_foods(s, query, limit),
            user_id=principal.user_id,
            readonly=True,
        )
        return {
            "results": [
                {
                    "food_id": str(r["food_id"]),
                    "name": r["name"],
                    "matched_alias": r["matched_alias"],
                    "default_portion": {
                        "unit_code": r["default_unit_code"],
                        "unit_size": r["default_size"],
                        "label": r["default_portion_label"],
                        "quantity": r["default_quantity"],
                        "basis": r["default_basis"],
                    },
                    "kcal_per_default": _int(r["kcal_per_default"]),
                }
                for r in rows
            ]
        }

    async def food(self, principal: Principal, food_id: UUID) -> dict[str, Any]:
        row = await self.db.run(
            lambda s: nutrition_repo.food_detail(s, food_id),
            user_id=principal.user_id,
            readonly=True,
        )
        if row is None:
            raise AppError(ErrorCode.NOT_FOUND)
        entitlement = await self.entitlements.get(principal.user_id)
        return {
            "food_id": str(row["food_id"]),
            "name": row["name"],
            "category_code": row["category_code"],
            "basis": row["basis"],
            "is_cooked": row["is_cooked"],
            "aliases": _obj(row["aliases"]),
            "portions": _obj(row["portions"]),
            "per_100": await self._view(entitlement.tier, _obj(row["nutrients"])),
        }

    async def barcode(self, principal: Principal, barcode: str) -> dict[str, Any]:
        entitlement = await self._require(principal, "barcode_logging")
        row = await self.db.run(
            lambda s: nutrition_repo.barcode_lookup(s, barcode),
            user_id=principal.user_id,
            readonly=True,
        )
        if row is None:
            product = await self.off.product(barcode)
            if product is None:
                return {"found": False, "barcode": barcode}

            async def cache(s: DbSession) -> Mapping[str, Any] | None:
                await nutrition_repo.upsert_barcode_product(
                    s,
                    principal.user_id,
                    barcode=barcode,
                    product_name=product.product_name,
                    brand=product.brand,
                    serving_g=product.serving_g,
                    nutrients=product.nutrients,
                )
                return await nutrition_repo.barcode_lookup(s, barcode)

            row = await self.db.run(cache, user_id=principal.user_id)
            if row is None:  # pragma: no cover - the upsert always leaves a row
                return {"found": False, "barcode": barcode}
        return {
            "found": True,
            "barcode": barcode,
            "product_name": row["product_name"],
            "brand": row["brand"],
            "food_id": str(row["food_id"]) if row["food_id"] else None,
            "serving_g": row["serving_g"],
            "source": row["source"],
            "per_100": await self._view(entitlement.tier, _obj(row["nutrients"])),
        }

    async def voice_parse(self, principal: Principal, transcript: str) -> dict[str, Any]:
        await self._require(principal, "voice_logging")
        parts = parse_transcript(transcript)
        if not parts:
            return {"items": [], "unmatched": []}

        async def work(
            s: DbSession,
        ) -> tuple[Sequence[Mapping[str, Any]], Sequence[Mapping[str, Any]]]:
            matches = await nutrition_repo.alias_match(s, [p.phrase for p in parts])
            food_ids = sorted({m["food_id"] for m in matches if m["food_id"]}, key=str)
            portions = await nutrition_repo.food_portions(s, food_ids) if food_ids else []
            return matches, portions

        matches, portions = await self.db.run(work, user_id=principal.user_id, readonly=True)
        by_food: dict[Any, list[Mapping[str, Any]]] = {}
        for p in portions:
            by_food.setdefault(p["food_id"], []).append(p)
        items: list[dict[str, Any]] = []
        unmatched: list[str] = []
        for part, match in zip(parts, matches, strict=True):
            if not match["food_id"] or Decimal(str(match["score"])) < VOICE_MIN_CONFIDENCE:
                unmatched.append(part.phrase)
                continue
            options = by_food.get(match["food_id"], [])
            chosen = next(
                (
                    o
                    for o in options
                    if o["unit_code"] == part.unit_code
                    and (part.unit_size is None or o["size"] == part.unit_size)
                ),
                None,
            )
            unit_found = chosen is not None or part.unit_code is None
            chosen = chosen or next((o for o in options if o["is_default"]), None)
            if chosen is None:
                unmatched.append(part.phrase)
                continue
            confidence = Decimal(str(match["score"])) * (1 if unit_found else Decimal("0.8"))
            items.append(
                {
                    "food_id": str(match["food_id"]),
                    "name": match["name"],
                    "quantity": part.quantity,
                    "unit_code": chosen["unit_code"],
                    "unit_size": chosen["size"],
                    "portion_label": chosen["label"],
                    "confidence": display_value("g", confidence * 100),
                }
            )
        return {"items": items, "unmatched": unmatched}

    # ------------------------------------------------------------------ meals
    async def preview(
        self, principal: Principal, items: Sequence[Mapping[str, Any]]
    ) -> dict[str, Any]:
        row = await self.db.run(
            lambda s: nutrition_repo.preview_meal(s, principal.user_id, items),
            user_id=principal.user_id,
            readonly=True,
        )
        entitlement = await self.entitlements.get(principal.user_id)
        row = row or {}
        totals = _obj(row.get("totals")) or {}
        return {
            "calories": _int(totals.get("calories")),
            "totals": await self._view(entitlement.tier, totals),
            "items": [
                {
                    "food_id": str(i["food_id"]),
                    "food_name": i["food_name"],
                    "quantity": Decimal(str(i["quantity"])),
                    "unit_code": i["unit_code"],
                    "unit_size": i["unit_size"],
                    "portion_label": i["portion_label"],
                    "consumed_amount": Decimal(str(i["consumed_amount"])),
                    "consumed_basis": i["consumed_basis"],
                    "calories": _int(i["nutrients"]["calories"]),
                }
                for i in _obj(row.get("items")) or []
            ],
        }

    async def log_meal(
        self, principal: Principal, body: Mapping[str, Any]
    ) -> tuple[bool, dict[str, Any]]:
        """(created, response). A replay of the same client_entry_id is not an error: the stored
        meal is returned with created = False (offline sync)."""
        source = body["source"]
        if source in {"voice", "barcode"}:
            await self._require(principal, f"{source}_logging")
        entitlement = await self.entitlements.get(principal.user_id)
        meal_id: UUID = body["client_entry_id"]

        async def work(
            s: DbSession,
        ) -> tuple[str, Mapping[str, Any] | None, Mapping[str, Any] | None]:
            status, local_date = await nutrition_repo.log_meal(
                s,
                principal.user_id,
                meal_id=meal_id,
                logged_at=body["logged_at"],
                meal_type=body["meal_type"],
                source=source,
                items=body["items"],
            )
            meal = await nutrition_repo.meal_breakdown(s, principal.user_id, meal_id)
            summary = await nutrition_repo.daily_summary(s, principal.user_id, local_date)
            return status, meal, summary

        try:
            status, meal, summary = await self.db.run(work, user_id=principal.user_id)
        except AppError as exc:
            if exc.code is ErrorCode.DAILY_LIMIT_REACHED:
                limit = entitlement.limits.get("meal_logs_per_day")
                raise AppError(
                    ErrorCode.DAILY_LIMIT_REACHED,
                    extra={"limit": limit} if limit is not None else None,
                ) from None
            raise
        if meal is None or summary is None:  # pragma: no cover - written in the same transaction
            raise AppError(ErrorCode.NOT_FOUND)
        daily = await self._summary_out(entitlement.tier, summary)
        return status == "created", {
            "meal": self.meal_out(meal),
            "daily_summary": daily,
            "avatar": daily["avatar"],
        }

    async def _current_meal(self, principal: Principal, meal_id: UUID) -> dict[str, Any] | None:
        row = await self.db.run(
            lambda s: nutrition_repo.meal_breakdown(s, principal.user_id, meal_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return self.meal_out(row) if row else None

    async def update_meal(
        self, principal: Principal, meal_id: UUID, version: int, body: Mapping[str, Any]
    ) -> dict[str, Any]:
        entitlement = await self.entitlements.get(principal.user_id)

        async def work(s: DbSession) -> tuple[Mapping[str, Any] | None, Mapping[str, Any] | None]:
            await nutrition_repo.update_meal(
                s,
                principal.user_id,
                meal_id,
                version=version,
                meal_type=body.get("meal_type"),
                items=body.get("items"),
            )
            meal = await nutrition_repo.meal_breakdown(s, principal.user_id, meal_id)
            day = meal["local_date"] if meal else None
            return meal, await nutrition_repo.daily_summary(s, principal.user_id, day)

        try:
            meal, summary = await self.db.run(work, user_id=principal.user_id)
        except AppError as exc:
            await self._enrich_conflict(principal, meal_id, exc)
            raise
        if meal is None or summary is None:  # pragma: no cover
            raise AppError(ErrorCode.NOT_FOUND)
        return {
            "meal": self.meal_out(meal),
            "daily_summary": await self._summary_out(entitlement.tier, summary),
        }

    async def delete_meal(self, principal: Principal, meal_id: UUID, version: int) -> None:
        try:
            await self.db.run(
                lambda s: nutrition_repo.delete_meal(s, principal.user_id, meal_id, version),
                user_id=principal.user_id,
            )
        except AppError as exc:
            await self._enrich_conflict(principal, meal_id, exc)
            raise

    async def _enrich_conflict(self, principal: Principal, meal_id: UUID, exc: AppError) -> None:
        if exc.code is ErrorCode.VERSION_CONFLICT:
            current = await self._current_meal(principal, meal_id)
            if current is not None:
                exc.extra["current"] = current

    async def meals_on(self, principal: Principal, on_date: date) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: nutrition_repo.meals_by_date(s, principal.user_id, on_date),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"date": on_date.isoformat(), "meals": [self.meal_out(r) for r in rows]}

    async def recent(self, principal: Principal, limit: int) -> dict[str, Any]:
        async def work(
            s: DbSession,
        ) -> tuple[Sequence[Mapping[str, Any]], Sequence[Mapping[str, Any]]]:
            return (
                await nutrition_repo.recent_meals(s, principal.user_id, limit),
                await nutrition_repo.recent_foods(s, principal.user_id, 10),
            )

        meals, foods = await self.db.run(work, user_id=principal.user_id, readonly=True)
        return {
            "meals": [self.meal_out(m) for m in meals],
            "recent_foods": [
                {
                    "food_id": str(f["food_id"]),
                    "name": f["name"],
                    "quantity": Decimal(str(f["quantity"])),
                    "unit_code": f["unit_code"],
                    "unit_size": f["unit_size"],
                }
                for f in foods
            ],
        }

    async def breakdown(self, principal: Principal, meal_id: UUID) -> dict[str, Any]:
        await self._require(principal, "meal_breakdown")
        row = await self.db.run(
            lambda s: nutrition_repo.meal_breakdown(s, principal.user_id, meal_id),
            user_id=principal.user_id,
            readonly=True,
        )
        if row is None:
            raise AppError(ErrorCode.NOT_FOUND)
        totals = _obj(row["totals"]) or {}
        macro_kcal = {
            k: Decimal(str(totals.get(k) or 0)) * per_g for k, per_g in MACRO_KCAL_PER_G.items()
        }
        all_kcal = sum(macro_kcal.values(), Decimal(0))
        return {
            "meal": self.meal_out(row),
            "totals": await self._view("star", totals),
            "macro_pct": {
                k: (display_value("kcal", v / all_kcal * 100) if all_kcal else Decimal(0))
                for k, v in macro_kcal.items()
            },
        }

    async def daily_summary(self, principal: Principal, on_date: date | None) -> dict[str, Any]:
        row = await self.db.run(
            lambda s: nutrition_repo.daily_summary(s, principal.user_id, on_date),
            user_id=principal.user_id,
            readonly=True,
        )
        if row is None:  # pragma: no cover - the function always returns a row
            raise AppError(ErrorCode.NOT_FOUND)
        entitlement = await self.entitlements.get(principal.user_id)
        return await self._summary_out(entitlement.tier, row)

    # ------------------------------------------------------------------ saved meals
    async def saved_meals(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: nutrition_repo.saved_meals(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {
            "saved_meals": [
                {
                    "saved_meal_id": str(r["saved_meal_id"]),
                    "name": r["name"],
                    "items": _obj(r["items"]),
                    "created_at": r["created_at"].isoformat(),
                }
                for r in rows
            ]
        }

    async def save_meal(
        self, principal: Principal, name: str, items: Sequence[Mapping[str, Any]]
    ) -> dict[str, Any]:
        saved_id = await self.db.run(
            lambda s: nutrition_repo.save_meal_template(s, principal.user_id, name, items),
            user_id=principal.user_id,
        )
        return {"saved_meal_id": str(saved_id)}

    async def delete_saved_meal(self, principal: Principal, saved_meal_id: UUID) -> None:
        await self.db.run(
            lambda s: nutrition_repo.delete_saved_meal(s, principal.user_id, saved_meal_id),
            user_id=principal.user_id,
        )

    # ------------------------------------------------------------------ staff
    async def admin_upsert_food(
        self, principal: Principal, food_id: UUID | None, fields: Mapping[str, Any]
    ) -> dict[str, Any]:
        new_id = await self.db.run(
            lambda s: nutrition_repo.admin_upsert_food(s, principal.user_id, food_id, fields),
            user_id=principal.user_id,
        )
        return {"food_id": str(new_id)}
