"""Rin AI chat (doc 04 section 2.10, doc 06 section 8, OQ-37 approved 2026-11-03, Session 13).

Order of a prompt:
1. Gate (before any streaming, so failures are normal JSON errors): RIN_ENABLED and a model, then
   the database gate (STAR rin_ai + ai_processing consent + onboarding) via the context read,
   then the monthly AI cap (403 MONTHLY_LIMIT_REACHED with resets_at = start of next local month;
   owner 2026-11-07: Rs 10 per user per month across all AI features).
2. The prompt is stored (idempotent by client_message_id; a replay answers with no new reply).
3. Emergency phrases get the fixed reply with India emergency numbers and no model call.
4. Model chain (owner 2026-11-11): RIN_MODEL first; when OUR OpenAI account rate-limits it or it
   fails, RIN_FALLBACK_MODEL (the lower model); when the account cannot answer at all (no credits,
   spending limit, bad key) or both fail, the free basic mode (basic_rin) answers from the user's
   own data so the chat never gets stuck. The per-user monthly cap is unchanged.
   Up to four model turns: text deltas stream to the app (lightly cleaned); proposal tools are
   validated (Pydantic + food database) and stored as pending actions, never as logs. Each turn's
   tokens and cost (from the configured prices) are recorded; the cap is the month's cost.
5. The full reply is cleaned to plain text (``to_plain_text``) and stored; ``done`` carries it and
   the usage %, so the app shows exactly what was stored.

Nothing here logs prompt or reply text: only ids, token counts and error class names.
"""

from __future__ import annotations

import json
import uuid
from collections.abc import AsyncIterator, Mapping, Sequence
from datetime import UTC, date, datetime, time
from typing import Annotated, Any, Literal
from uuid import UUID

import structlog
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.authz import Principal
from app.core.security.validators import Kind, safe
from app.domain.ai import basic_rin
from app.domain.ai.guardrails import (
    REFUSAL_REPLY,
    emergency_reply,
    off_topic_reply,
    strip_delta,
    to_plain_text,
)
from app.domain.ai.pricing import AiPrices
from app.domain.ai.prompting import SYSTEM_PROMPT, context_block, history_messages
from app.domain.ai.rin_model import (
    DRINK_CODES,
    RinModel,
    TextDelta,
    ToolCall,
    TurnDone,
    Usage,
    failure_kind,
)
from app.domain.hydration.service import HydrationService
from app.domain.nutrition.meal_type import suggest_meal_type
from app.domain.nutrition.service import NutritionService
from app.repositories import nutrition_repo, rin_repo
from app.repositories.base import Database, DbSession

log = structlog.get_logger(__name__)

MAX_TURNS = 4  # room for a data lookup, a log proposal and the answer
BASIC_MODEL = "rin-basic"  # usage rows of basic-mode replies (priced like the main model)
CHARS_PER_TOKEN = 4  # rough token estimate for basic-mode replies
FoodName = Annotated[str, safe(Kind.SEARCH, 64)]


class _ProposedFood(BaseModel):
    model_config = ConfigDict(extra="ignore")

    food_name: FoodName
    quantity: float = Field(gt=0, le=20)
    unit: str = Field(max_length=40)


class _MealProposal(BaseModel):
    model_config = ConfigDict(extra="ignore")

    items: list[_ProposedFood] = Field(min_length=1, max_length=10)


class _DataRequest(BaseModel):
    model_config = ConfigDict(extra="ignore")

    kind: Literal["day", "period", "meals"]
    day: date | None = Field(default=None, alias="date")
    days: int | None = Field(default=None, ge=1, le=90)


class _DrinkProposal(BaseModel):
    model_config = ConfigDict(extra="ignore")

    drink: Literal["water", "tea", "milk", "coconut_water", "coffee", "juice"]
    volume_ml: int = Field(ge=50, le=2000)


class _Attempt:
    """What one model's attempt produced (text so far, the proposal it created)."""

    def __init__(self) -> None:
        self.text_parts: list[str] = []
        self.action_id: UUID | None = None


def sse(event: str, data: Mapping[str, Any]) -> str:
    """One Server-Sent Event; data is JSON (never raw model text outside a JSON string)."""
    return f"event: {event}\ndata: {json.dumps(dict(data), default=str, ensure_ascii=False)}\n\n"


class RinService:
    def __init__(
        self,
        *,
        db: Database,
        model: RinModel | None,
        nutrition: NutritionService,
        hydration: HydrationService,
        budget_micro_inr: int,
        prices: AiPrices,
        enabled: bool,
        fallback_model: RinModel | None = None,
        fallback_prices: AiPrices | None = None,
    ) -> None:
        self.db = db
        self.model = model
        self.fallback_model = fallback_model
        self.fallback_prices = fallback_prices or prices
        self.nutrition = nutrition
        self.hydration = hydration
        self.budget = budget_micro_inr
        self.prices = prices
        self.enabled = enabled

    # -------------------------------------------------------------- usage and gate
    def _pct(self, used: int) -> float:
        """Share of the monthly limit used, one decimal, for the bar (one small reply is about
        0.2 %, so whole percents looked stuck): any use shows at least 0.1 %, and 100 % only once
        the limit is really reached."""
        if self.budget <= 0 or used >= self.budget:
            return 100.0
        if used <= 0:
            return 0.0
        return min(99.9, max(0.1, round(used * 100 / self.budget, 1)))

    async def usage(self, principal: Principal) -> dict[str, Any]:
        used, resets_at, _ = await self.db.run(
            lambda s: rin_repo.usage_month(s, principal.user_id),
            user_id=principal.user_id,
            readonly=True,
        )
        return {"used_pct": self._pct(used), "resets_at": resets_at}

    async def allowance_left(self, user_id: UUID) -> bool:
        """For the other AI features (drink estimate): False when this month's cap is used up."""
        used, _, _ = await self.db.run(
            lambda s: rin_repo.usage_month(s, user_id), user_id=user_id, readonly=True
        )
        return used < self.budget

    async def record(self, user_id: UUID, feature: str, model: str, usage: Usage) -> None:
        lower = self.fallback_model is not None and model == self.fallback_model.model
        cost = (self.fallback_prices if lower else self.prices).cost_micro_inr(usage)
        await self.db.run(
            lambda s: rin_repo.record_usage(
                s,
                user_id,
                feature=feature,
                model=model,
                input_tokens=usage.input_tokens,
                output_tokens=usage.output_tokens,
                cache_write_tokens=usage.cache_write_tokens,
                cache_read_tokens=usage.cache_read_tokens,
                cost_micro_inr=cost,
            ),
            user_id=user_id,
        )

    async def _gate(self, principal: Principal) -> tuple[dict[str, Any], datetime]:
        if not self.enabled:  # the kill switch; without a key Rin still answers in basic mode
            raise AppError(ErrorCode.SERVICE_UNAVAILABLE)

        async def work(s: DbSession) -> tuple[dict[str, Any], int, datetime, datetime]:
            context = await rin_repo.context(s, principal.user_id)  # STAR + consent gate
            used, resets_at, midnight = await rin_repo.usage_month(s, principal.user_id)
            return context, used, resets_at, midnight

        context, used, resets_at, midnight = await self.db.run(
            work, user_id=principal.user_id, readonly=True
        )
        if used >= self.budget:
            raise AppError(
                ErrorCode.MONTHLY_LIMIT_REACHED, extra={"resets_at": resets_at, "used_pct": 100}
            )
        return context, midnight

    # -------------------------------------------------------------- reads
    async def conversations(
        self, principal: Principal, *, query: str | None, before: datetime | None, limit: int
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: rin_repo.conversations(
                s, principal.user_id, query=query, before=before, limit=limit
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        next_before = rows[-1]["last_message_at"] if len(rows) == limit else None
        return {"items": rows, "next_before": next_before}

    async def messages(
        self, principal: Principal, conversation_id: UUID, *, before: datetime | None, limit: int
    ) -> dict[str, Any]:
        rows = await self.db.run(
            lambda s: rin_repo.messages(
                s, principal.user_id, conversation_id, before=before, limit=limit
            ),
            user_id=principal.user_id,
            readonly=True,
        )
        next_before = rows[-1]["created_at"] if len(rows) == limit else None
        return {"items": rows, "next_before": next_before}

    async def create_conversation(self, principal: Principal, title: str | None) -> UUID:
        return await self.db.run(
            lambda s: rin_repo.create_conversation(s, principal.user_id, title or "New chat"),
            user_id=principal.user_id,
        )

    async def delete_conversation(self, principal: Principal, conversation_id: UUID) -> None:
        await self.db.run(
            lambda s: rin_repo.delete_conversation(s, principal.user_id, conversation_id),
            user_id=principal.user_id,
        )

    async def delete_memory(self, principal: Principal) -> None:
        await self.db.run(
            lambda s: rin_repo.delete_memory(s, principal.user_id), user_id=principal.user_id
        )

    # -------------------------------------------------------------- chat
    async def start(
        self,
        principal: Principal,
        conversation_id: UUID,
        prompt: str,
        client_message_id: UUID,
    ) -> AsyncIterator[str]:
        """Checks and stores the prompt now (errors become JSON responses), then returns the SSE
        stream of the reply. A new chat is created first (POST /rin/conversations); the database
        titles it from its first prompt."""
        context, next_midnight = await self._gate(principal)
        user_id = principal.user_id
        _, status = await self.db.run(
            lambda s: rin_repo.append_message(
                s,
                user_id,
                conversation_id,
                role="user",
                content=prompt,
                client_message_id=client_message_id,
            ),
            user_id=user_id,
        )
        return self._reply(
            principal,
            conversation_id,
            prompt,
            context,
            next_midnight,
            duplicate=status != "created",
        )

    async def _reply(
        self,
        principal: Principal,
        conversation_id: UUID,
        prompt: str,
        context: Mapping[str, Any],
        next_midnight: datetime,
        *,
        duplicate: bool,
    ) -> AsyncIterator[str]:
        user_id = principal.user_id
        yield sse("start", {"conversation_id": conversation_id})
        if duplicate:  # replay of a prompt already answered (retry after a lost connection)
            yield sse("done", {"conversation_id": conversation_id, "duplicate": True})
            return
        # Fixed replies, no model call (and no AI cost): emergencies first, then requests that are
        # clearly outside Rin's scope (code and other tech help).
        fixed = emergency_reply(prompt) or off_topic_reply(prompt)
        if fixed is not None:
            await self._store_reply(user_id, conversation_id, fixed, None)
            yield sse("delta", {"text": fixed})
            yield sse("done", await self._done(user_id, conversation_id, fixed))
            return
        history = await self.db.run(
            lambda s: rin_repo.history(s, user_id, conversation_id),
            user_id=user_id,
            readonly=True,
        )
        messages = history_messages(history)
        # Local wall time from the next local midnight (no timezone lookup needed).
        seconds = max(0, int(86400 - (next_midnight - datetime.now(UTC)).total_seconds()))
        local_now = time((seconds // 3600) % 24, (seconds % 3600) // 60)
        models = [m for m in (self.model, self.fallback_model) if m is not None]
        attempt: _Attempt | None = None
        for model in models:
            current = _Attempt()
            try:
                async for chunk in self._model_turns(
                    model,
                    user_id,
                    conversation_id,
                    context=context,
                    messages=messages,
                    local_now=local_now,
                    state=current,
                ):
                    yield chunk
            except Exception as exc:  # provider or network failure
                kind = failure_kind(exc)
                log.warning(
                    "rin_model_failed", model=model.model, error=type(exc).__name__, kind=kind
                )
                if kind != "retry":
                    # Our OpenAI account cannot answer (no credits / spending limit / key): every
                    # model would fail, so go straight to basic mode. Owner action: top up.
                    log.error("openai_account_unavailable", kind=kind)
                if current.text_parts:  # part of an answer already reached the user: keep it
                    attempt = current
                    break
                if kind != "retry":
                    break
                continue
            attempt = current
            break
        if attempt is None:
            async for chunk in self._basic_reply(
                user_id, conversation_id, prompt, context, local_now
            ):
                yield chunk
            return
        reply = to_plain_text("".join(attempt.text_parts) or "Done.")
        await self._store_reply(user_id, conversation_id, reply, attempt.action_id)
        yield sse("done", await self._done(user_id, conversation_id, reply))

    async def _model_turns(
        self,
        model: RinModel,
        user_id: UUID,
        conversation_id: UUID,
        *,
        context: Mapping[str, Any],
        messages: list[dict[str, Any]],
        local_now: time,
        state: _Attempt,
    ) -> AsyncIterator[str]:
        """Up to MAX_TURNS turns of one model; provider errors propagate to the chain."""
        for _turn in range(MAX_TURNS):
            result = None
            async for event in model.stream_turn(
                system=SYSTEM_PROMPT, context=context_block(context), messages=messages
            ):
                if isinstance(event, TextDelta):
                    state.text_parts.append(event.text)
                    cleaned = strip_delta(event.text)
                    if cleaned:
                        yield sse("delta", {"text": cleaned})
                elif isinstance(event, TurnDone):
                    result = event.result
            if result is None:
                return
            await self.record(user_id, "chat", model.model, result.usage)
            if result.stop_reason == "refusal":
                state.text_parts = [REFUSAL_REPLY]
                return
            if not result.tool_calls or result.stop_reason == "max_tokens":
                return
            outputs: list[tuple[str, str]] = []
            for call in result.tool_calls:
                outcome, action = await self._handle_tool(user_id, conversation_id, call, local_now)
                if action is not None:
                    state.action_id = action["action_id"]
                    yield sse("action", action)
                outputs.append((call.id, outcome))
            messages = [*messages, *model.followup(result, outputs)]

    async def _basic_reply(
        self,
        user_id: UUID,
        conversation_id: UUID,
        prompt: str,
        context: Mapping[str, Any],
        local_now: time,
    ) -> AsyncIterator[str]:
        """Free answer without AI (basic_rin): today's numbers, tips, or a log proposal card."""
        reply = basic_rin.answer(prompt, dict(context))
        text, action_id = reply.text, None
        call: ToolCall | None = None
        if reply.drink is not None:
            call = ToolCall(id="basic", name="propose_drink_log", input=reply.drink)
        elif reply.meal_items:
            call = ToolCall(id="basic", name="propose_meal_log", input={"items": reply.meal_items})
        if call is not None:
            _, action = await self._handle_tool(user_id, conversation_id, call, local_now)
            if action is None:
                text = (
                    "I couldn't match that to foods I know. Try simple names like roti, dal or "
                    "apple."
                )
            else:
                action_id = action["action_id"]
                yield sse("action", action)
        # Counts toward the user's monthly limit like an AI reply of the same size (owner
        # 2026-11-11): tokens estimated from the text (about 4 characters a token) and priced at
        # the main model's prices, recorded as model "rin-basic".
        estimate = Usage(
            input_tokens=len(SYSTEM_PROMPT + context_block(context) + prompt) // CHARS_PER_TOKEN,
            output_tokens=max(1, len(text) // CHARS_PER_TOKEN),
        )
        await self.record(user_id, "chat", BASIC_MODEL, estimate)
        await self._store_reply(user_id, conversation_id, text, action_id)
        yield sse("delta", {"text": text})
        done = await self._done(user_id, conversation_id, text)
        yield sse("done", {**done, "mode": "basic"})

    async def _store_reply(
        self, user_id: UUID, conversation_id: UUID, text: str, action_id: UUID | None
    ) -> None:
        await self.db.run(
            lambda s: rin_repo.append_message(
                s, user_id, conversation_id, role="assistant", content=text, action_id=action_id
            ),
            user_id=user_id,
        )

    async def _done(self, user_id: UUID, conversation_id: UUID, text: str) -> dict[str, Any]:
        used, resets_at, _ = await self.db.run(
            lambda s: rin_repo.usage_month(s, user_id), user_id=user_id, readonly=True
        )
        return {
            "conversation_id": conversation_id,
            "text": text,
            "usage_pct": self._pct(used),
            "resets_at": resets_at,
        }

    # -------------------------------------------------------------- tools
    async def _handle_tool(
        self, user_id: UUID, conversation_id: UUID, call: ToolCall, local_now: time
    ) -> tuple[str, dict[str, Any] | None]:
        """(tool_result text for the model, action event for the app or None)."""
        if call.name == "get_my_data":
            return await self._lookup(user_id, call.input), None
        try:
            if call.name == "propose_meal_log":
                proposal = _MealProposal.model_validate(call.input)
                payload = await self._meal_payload(user_id, proposal, local_now)
                if payload is None:
                    return "No matching foods were found; ask the user to describe it again.", None
                kind = "meal"
            elif call.name == "propose_drink_log":
                drink = _DrinkProposal.model_validate(call.input)
                payload = {"drink_code": drink.drink, "volume_ml": drink.volume_ml}
                kind = "drink"
            else:
                return "Unknown tool.", None
        except ValidationError:
            return "The proposal was not valid; ask the user to rephrase.", None
        action_id, expires_at = await self.db.run(
            lambda s: rin_repo.create_action(s, user_id, conversation_id, kind, payload),
            user_id=user_id,
        )
        return (
            "A confirmation card is now shown to the user; nothing is logged until they accept.",
            {
                "action_id": action_id,
                "kind": kind,
                "payload": payload,
                "status": "pending",
                "expires_at": expires_at,
            },
        )

    async def _lookup(self, user_id: UUID, raw: Any) -> str:
        """The user's own data for the model (numbers and catalogue names only), as JSON."""
        try:
            request = _DataRequest.model_validate(raw)
            data = await self.db.run(
                lambda s: rin_repo.lookup(
                    s, user_id, kind=request.kind, day=request.day, days=request.days
                ),
                user_id=user_id,
                readonly=True,
            )
        except (ValidationError, AppError):
            return "That data is not available: use a date within the last 90 days or 1-90 days."
        return json.dumps(data, ensure_ascii=False, default=str)

    async def _meal_payload(
        self, user_id: UUID, proposal: _MealProposal, local_now: time
    ) -> dict[str, Any] | None:
        """Maps proposed names to foods (best search match, default portion), then prices the meal
        with the normal preview so the card shows server numbers."""

        async def work(s: DbSession) -> dict[str, Any] | None:
            items: list[dict[str, Any]] = []
            unmatched: list[str] = []
            for p in proposal.items:
                found = await nutrition_repo.search_foods(s, p.food_name, 1)
                if not found:
                    unmatched.append(p.food_name)
                    continue
                f = found[0]
                items.append(
                    {
                        "food_id": str(f["food_id"]),
                        "quantity": round(p.quantity, 2),
                        "unit_code": f["default_unit_code"],
                        "unit_size": f["default_size"],
                    }
                )
            if not items:
                return None
            preview = await nutrition_repo.preview_meal(s, user_id, items) or {}
            totals = preview.get("totals")
            totals = json.loads(totals) if isinstance(totals, str) else (totals or {})
            rows = preview.get("items")
            rows = json.loads(rows) if isinstance(rows, str) else (rows or [])
            return {
                "meal_type": suggest_meal_type(local_now),
                "items": [
                    {
                        "food_id": str(r["food_id"]),
                        "food_name": r["food_name"],
                        "quantity": float(r["quantity"]),
                        "unit_code": r["unit_code"],
                        "unit_size": r["unit_size"],
                        "portion_label": r["portion_label"],
                        "calories": round(float(r["nutrients"]["calories"] or 0)),
                    }
                    for r in rows
                ],
                "totals": {
                    k: round(float(totals.get(k) or 0))
                    for k in ("calories", "protein", "carbohydrates", "fat")
                },
                "unmatched": unmatched,
            }

        return await self.db.run(work, user_id=user_id, readonly=True)

    # -------------------------------------------------------------- actions
    async def accept_action(
        self, principal: Principal, action_id: UUID, items: Sequence[Mapping[str, Any]] | None
    ) -> dict[str, Any]:
        """Logs the proposal through the normal meal / drink path (source 'rin', limits apply),
        then marks the action accepted. ``items`` replaces the meal items when the user edited
        them."""
        action = await self.db.run(
            lambda s: rin_repo.pending_action(s, principal.user_id, action_id),
            user_id=principal.user_id,
            readonly=True,
        )
        if action["status"] != "pending":
            raise AppError(ErrorCode.ACTION_RESOLVED)
        if action["expired"]:
            raise AppError(ErrorCode.ACTION_EXPIRED)
        payload = action["payload"] or {}
        entry_id = uuid.uuid5(action_id, "log")  # replays reuse the same entry (idempotent log)
        now = datetime.now(UTC)
        if action["kind"] == "meal":
            meal_items = [
                {
                    "food_id": UUID(str(i["food_id"])),
                    "quantity": i["quantity"],
                    "unit_code": i["unit_code"],
                    "unit_size": i.get("unit_size"),
                }
                for i in (items if items is not None else payload["items"])
            ]
            _, result = await self.nutrition.log_meal(
                principal,
                {
                    "client_entry_id": entry_id,
                    "logged_at": now,
                    "meal_type": payload.get("meal_type", "snack"),
                    "source": "rin",
                    "items": meal_items,
                },
            )
        else:
            if payload.get("drink_code") not in DRINK_CODES:
                raise AppError(ErrorCode.VALIDATION_FAILED)
            _, result = await self.hydration.log_intake(
                principal,
                {
                    "client_entry_id": entry_id,
                    "logged_at": now,
                    "drink_code": payload["drink_code"],
                    "custom_drink_id": None,
                    "volume_ml": int(payload["volume_ml"]),
                    "source": "rin",
                },
            )
        await self.db.run(
            lambda s: rin_repo.resolve_action(
                s, principal.user_id, action_id, "accepted", entry_id
            ),
            user_id=principal.user_id,
        )
        return {"action_id": action_id, "status": "accepted", "result": result}

    async def dismiss_action(self, principal: Principal, action_id: UUID) -> None:
        await self.db.run(
            lambda s: rin_repo.resolve_action(s, principal.user_id, action_id, "dismissed", None),
            user_id=principal.user_id,
        )
