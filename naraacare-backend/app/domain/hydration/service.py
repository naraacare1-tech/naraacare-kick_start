"""Hydration tracking and workouts (doc 04 section 2.5, doc 06 section 3, Session 09).

* The status is computed here from ``hydration.fn_day_inputs`` by the pure engine
  (``status.compute``); the database stores the entries, enforces tiers, limits and the edit rule,
  and keeps the daily totals. Each status read also records the day's need, food water and first
  goal completion (``hydration.pr_upsert_daily_summary``) for reports and the S12 feed.
* Tier rules (doc 04 section 3, OQ-04/OQ-05): temperature and workouts need ``advanced_hydration``,
  STAR drinks ``premium_drinks``, custom drinks ``custom_drinks``; a 403 carries ``feature``. The
  database checks the same entitlements again inside its transactions.
* Errors are enriched like meals: the server copy as ``current`` on 409 VERSION_CONFLICT.
"""

from __future__ import annotations

from collections.abc import Mapping
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any, Protocol
from uuid import UUID

import structlog

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.domain.ai.drink_estimator import DrinkEstimator
from app.domain.ai.rin_model import Usage
from app.domain.common.calc_context import CalcContext
from app.domain.entitlements.service import EntitlementService
from app.domain.hydration import status as engine
from app.domain.reference import ReferenceCache
from app.repositories import hydration_repo, privacy_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)

PREMIUM_DRINKS = frozenset({"coffee", "juice", "beer"})


def _num(value: Any) -> float:
    return float(value) if value is not None else 0.0


def intake_out(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "intake_id": str(row["intake_id"]),
        "logged_at": row["logged_at"].isoformat(),
        "date": row["local_date"].isoformat(),
        "drink_code": row["drink_code"],
        "custom_drink_id": str(row["custom_drink_id"]) if row["custom_drink_id"] else None,
        "label": row["label"],
        "volume_ml": int(row["volume_ml"]),
        "hydration_factor": _num(row["hydration_factor"]),
        "effective_ml": _num(row["effective_ml"]),
        "source": row["source"],
        "version": int(row["version"]),
        "editable": bool(row["editable"]),
    }


def workout_out(row: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "workout_id": str(row["workout_id"]),
        "performed_at": row["performed_at"].isoformat(),
        "date": row["local_date"].isoformat(),
        "workout_type": row["workout_type"],
        "label": row["label"],
        "duration_min": int(row["duration_min"]),
        "sweat_ml": _num(row["sweat_ml"]),
        "kcal": int(row["kcal"]),
        "version": int(row["version"]),
        "editable": bool(row["editable"]),
    }


class AiMeter(Protocol):
    """The monthly AI cap (RinService): checked before and charged after a model call."""

    async def allowance_left(self, user_id: UUID) -> bool: ...

    async def record(self, user_id: UUID, feature: str, model: str, usage: Usage) -> None: ...


class HydrationService:
    def __init__(
        self,
        *,
        db: Database,
        reference: ReferenceCache,
        entitlements: EntitlementService,
        estimator: DrinkEstimator,
    ) -> None:
        self.db = db
        self.reference = reference
        self.entitlements = entitlements
        self.estimator = estimator
        # Set by the Rin wiring: the monthly AI cap and its metering (None: not metered).
        self.ai_meter: AiMeter | None = None

    # ------------------------------------------------------------------ helpers
    async def _require(self, principal: Principal, feature: str) -> None:
        entitlement = await self.entitlements.get(principal.user_id)
        if not entitlement.allows(feature):
            raise AppError(ErrorCode.UPGRADE_REQUIRED, extra={"feature": feature})

    async def _ctx(self) -> CalcContext:
        return await self.reference.calc_context()

    async def _status_in(
        self, s: DbSession, user_id: UUID, ctx: CalcContext, on_date: date | None
    ) -> dict[str, Any]:
        """Compute the day's status and record its summary, inside the caller's transaction."""
        raw = await hydration_repo.day_inputs(s, user_id, on_date)
        day = engine.DayInputs.from_db(raw)
        result = engine.compute(ctx, day, datetime.now(UTC))
        first = await hydration_repo.upsert_summary(
            s,
            user_id,
            on_date=day.day,
            need_ml=round(result.daily_goal_ml),
            food_water_ml=Decimal(f"{result.food_water_ml:.1f}"),
            goal_completed=result.goal_completed,
            calc_version=day.calc_version,
        )
        if first:
            # The S12 feed subscribes to this event; it carries no health values.
            log.info("hydration_goal_completed", local_date=day.day.isoformat())
        out = engine.to_json(result, day.temperature_unit)
        out["date"] = day.day.isoformat()
        out["tier"] = raw.get("tier")
        out["advanced"] = day.advanced
        return out

    async def status(self, principal: Principal, on_date: date | None = None) -> dict[str, Any]:
        ctx = await self._ctx()
        return await self.db.run(
            lambda s: self._status_in(s, principal.user_id, ctx, on_date), user_id=principal.user_id
        )

    # ------------------------------------------------------------------ drinks
    async def drinks(self, principal: Principal) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: hydration_repo.drinks(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        ctx = await self._ctx()
        standard, custom = [], []
        for r in rows:
            item = {
                "label": r["label"],
                "hydration_factor": _num(r["hydration_factor"]),
                "tier_required": r["tier_required"],
                "locked": bool(r["locked"]),
            }
            if r["kind"] == "standard":
                standard.append(
                    {"drink_code": r["drink_code"], "is_alcohol": bool(r["is_alcohol"]), **item}
                )
            else:
                custom.append({"custom_drink_id": str(r["custom_drink_id"]), **item})
        return {
            "drinks": standard,
            "custom_drinks": custom,
            "presets_ml": [100, 250, 500],
            "quick_add_ml": int(ctx.f("hyd.quick_add_ml")),
        }

    async def log_intake(
        self, principal: Principal, body: Mapping[str, Any]
    ) -> tuple[bool, dict[str, Any]]:
        """(created, {intake, status}); a replay of the same client_entry_id returns the stored
        drink with created = False (offline sync)."""
        if body.get("drink_code") in PREMIUM_DRINKS:
            await self._require(principal, "premium_drinks")
        if body.get("custom_drink_id") is not None:
            await self._require(principal, "custom_drinks")
        ctx = await self._ctx()
        intake_id: UUID = body["client_entry_id"]

        async def work(s: DbSession) -> tuple[str, Mapping[str, Any] | None, dict[str, Any]]:
            status, local_date = await hydration_repo.log_intake(
                s,
                principal.user_id,
                intake_id=intake_id,
                logged_at=body["logged_at"],
                drink_code=body.get("drink_code"),
                custom_drink_id=body.get("custom_drink_id"),
                volume_ml=body["volume_ml"],
                source=body["source"],
            )
            rows = await hydration_repo.intakes(s, principal.user_id, None, intake_id)
            return (
                status,
                rows[0] if rows else None,
                await self._status_in(s, principal.user_id, ctx, local_date),
            )

        status, row, day_status = await self.db.run(work, user_id=principal.user_id)
        if row is None:  # pragma: no cover - written in the same transaction
            raise AppError(ErrorCode.NOT_FOUND)
        return status == "created", {"intake": intake_out(row), "status": day_status}

    async def _current_intake(self, principal: Principal, intake_id: UUID) -> dict[str, Any] | None:
        rows = await self.db.run(
            lambda s: hydration_repo.intakes(s, principal.user_id, None, intake_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return intake_out(rows[0]) if rows else None

    async def update_intake(
        self, principal: Principal, intake_id: UUID, version: int, body: Mapping[str, Any]
    ) -> dict[str, Any]:
        if body.get("drink_code") in PREMIUM_DRINKS:
            await self._require(principal, "premium_drinks")
        if body.get("custom_drink_id") is not None:
            await self._require(principal, "custom_drinks")
        ctx = await self._ctx()

        async def work(s: DbSession) -> tuple[Mapping[str, Any] | None, dict[str, Any]]:
            await hydration_repo.update_intake(
                s,
                principal.user_id,
                intake_id,
                version=version,
                volume_ml=body.get("volume_ml"),
                drink_code=body.get("drink_code"),
                custom_drink_id=body.get("custom_drink_id"),
            )
            rows = await hydration_repo.intakes(s, principal.user_id, None, intake_id)
            row = rows[0] if rows else None
            day = row["local_date"] if row else None
            return row, await self._status_in(s, principal.user_id, ctx, day)

        try:
            row, day_status = await self.db.run(work, user_id=principal.user_id)
        except AppError as exc:
            await self._enrich_conflict(principal, intake_id, exc)
            raise
        if row is None:  # pragma: no cover
            raise AppError(ErrorCode.NOT_FOUND)
        return {"intake": intake_out(row), "status": day_status}

    async def delete_intake(self, principal: Principal, intake_id: UUID, version: int) -> None:
        try:
            await self.db.run(
                lambda s: hydration_repo.delete_intake(s, principal.user_id, intake_id, version),
                user_id=principal.user_id,
            )
        except AppError as exc:
            await self._enrich_conflict(principal, intake_id, exc)
            raise

    async def _enrich_conflict(self, principal: Principal, intake_id: UUID, exc: AppError) -> None:
        if exc.code is ErrorCode.VERSION_CONFLICT:
            current = await self._current_intake(principal, intake_id)
            if current is not None:
                exc.extra["current"] = current

    async def intakes_on(self, principal: Principal, on_date: date) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: hydration_repo.intakes(s, principal.user_id, on_date),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"date": on_date.isoformat(), "items": [intake_out(r) for r in rows]}

    # ------------------------------------------------------------------ STAR inputs
    async def set_temperature(self, principal: Principal, temperature_c: Decimal) -> dict[str, Any]:
        await self._require(principal, "advanced_hydration")
        ctx = await self._ctx()

        async def work(s: DbSession) -> dict[str, Any]:
            local_date = await hydration_repo.set_temperature(s, principal.user_id, temperature_c)
            return await self._status_in(s, principal.user_id, ctx, local_date)

        return await self.db.run(work, user_id=principal.user_id)

    async def estimate_custom_drink(self, principal: Principal, name: str) -> dict[str, Any]:
        """STAR. Only the name goes to the model, and only with the user's AI consent; otherwise
        the product default (0.85) is offered. The user confirms before saving."""
        await self._require(principal, "custom_drinks")
        consents = await self.db.run(
            lambda s: privacy_repo.current_consents(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        default = (await self._ctx()).const("hyd.custom_drink.default_factor")
        if not any(c["purpose"] == "ai_processing" and c["granted"] for c in consents):
            return {
                "hydration_factor": float(default),
                "source": "default",
                "explanation_code": "ai_consent_missing",
            }
        meter = self.ai_meter
        if meter is not None and not await meter.allowance_left(principal.user_id):
            # This month's AI cap is used up: offer the product default, no model call.
            return {
                "hydration_factor": float(default),
                "source": "default",
                "explanation_code": "unknown",
            }

        async def record(model: str, usage: Usage) -> None:
            if meter is not None:
                await meter.record(principal.user_id, "drink_estimate", model, usage)

        estimate = await self.estimator.estimate(name, default, record)
        return {
            "hydration_factor": float(estimate.hydration_factor),
            "source": estimate.source,
            "explanation_code": estimate.explanation_code,
        }

    async def save_custom_drink(
        self, principal: Principal, body: Mapping[str, Any]
    ) -> dict[str, Any]:
        await self._require(principal, "custom_drinks")
        factor = Decimal(body["hydration_factor"]).quantize(Decimal("0.001"))
        drink_id = await self.db.run(
            lambda s: hydration_repo.save_custom_drink(
                s,
                principal.user_id,
                name=body["name"],
                factor=factor,
                estimated_by=body.get("source", "user"),
            ),
            user_id=principal.user_id,
        )
        return {
            "custom_drink_id": str(drink_id),
            "label": body["name"],
            "hydration_factor": float(factor),
            "tier_required": "star",
            "locked": False,
        }

    # ------------------------------------------------------------------ workouts
    async def log_workout(
        self, principal: Principal, body: Mapping[str, Any]
    ) -> tuple[bool, dict[str, Any]]:
        await self._require(principal, "advanced_hydration")
        ctx = await self._ctx()
        workout_id: UUID = body["client_entry_id"]

        async def work(s: DbSession) -> tuple[str, Mapping[str, Any] | None, dict[str, Any]]:
            status, local_date = await hydration_repo.log_workout(
                s,
                principal.user_id,
                workout_id=workout_id,
                performed_at=body["performed_at"],
                workout_type=body["workout_type"],
                duration_min=body["duration_min"],
            )
            rows = await hydration_repo.workouts(s, principal.user_id, None, workout_id)
            return (
                status,
                rows[0] if rows else None,
                await self._status_in(s, principal.user_id, ctx, local_date),
            )

        status, row, day_status = await self.db.run(work, user_id=principal.user_id)
        if row is None:  # pragma: no cover
            raise AppError(ErrorCode.NOT_FOUND)
        out = workout_out(row)
        return status == "created", {
            "workout": out,
            "sweat_ml": out["sweat_ml"],
            "kcal": out["kcal"],
            "status": day_status,
        }

    async def workouts_on(self, principal: Principal, on_date: date) -> dict[str, Any]:
        await self._require(principal, "advanced_hydration")
        rows = await self.db.run(
            lambda s: hydration_repo.workouts(s, principal.user_id, on_date),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"date": on_date.isoformat(), "items": [workout_out(r) for r in rows]}

    async def delete_workout(self, principal: Principal, workout_id: UUID, version: int) -> None:
        try:
            await self.db.run(
                lambda s: hydration_repo.delete_workout(s, principal.user_id, workout_id, version),
                user_id=principal.user_id,
            )
        except AppError as exc:
            if exc.code is ErrorCode.VERSION_CONFLICT:
                rows = await self.db.run(
                    lambda s: hydration_repo.workouts(s, principal.user_id, None, workout_id),
                    user_id=principal.user_id,
                    readonly=True,
                )
                if rows:
                    exc.extra["current"] = workout_out(rows[0])
            raise
