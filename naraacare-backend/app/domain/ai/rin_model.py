"""The model behind Rin AI (owner 2026-11-07: OpenAI GPT-5 mini via the official ``openai`` SDK).

* One Chat Completions request per turn, streamed; text deltas are passed on as they arrive and the
  final chunk gives the token usage (``stream_options.include_usage``).
* Two proposal tools with strict schemas. They never write anything: the server validates the
  input and stores a pending action the user must accept. ``tool_choice`` stays auto.
* The stable system prompt is sent first so OpenAI's automatic prompt caching reuses it across
  turns (cached input costs a tenth); the per-user context follows it.
* ``RinModel`` is the seam for tests: a fake yields scripted events, no network. ``followup``
  builds the messages that carry tool results back, in the provider's own shape.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass, field
from typing import Any, Protocol, cast

import openai
from openai import AsyncOpenAI
from openai.types.chat import ChatCompletionMessageParam, ChatCompletionToolParam

DRINK_CODES = ("water", "tea", "milk", "coconut_water", "coffee", "juice")

TOOLS: list[ChatCompletionToolParam] = [
    {
        "type": "function",
        "function": {
            "name": "propose_meal_log",
            "description": (
                "Propose logging foods the user says they ate or are about to eat. The app shows "
                "the user a card with the estimate; nothing is logged until they tap Add to "
                "Avatar. Use simple common food names (e.g. 'roti', 'dal', 'apple') and the amount "
                "they said."
            ),
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "items": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "food_name": {"type": "string"},
                                "quantity": {"type": "number"},
                                "unit": {"type": "string"},
                            },
                            "required": ["food_name", "quantity", "unit"],
                            "additionalProperties": False,
                        },
                    },
                },
                "required": ["items"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "propose_drink_log",
            "description": (
                "Propose logging a drink the user says they had. The app shows a card; nothing is "
                "logged until they confirm."
            ),
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "drink": {"type": "string", "enum": list(DRINK_CODES)},
                    "volume_ml": {"type": "integer"},
                },
                "required": ["drink", "volume_ml"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "get_my_data",
            "description": (
                "Read the user's own logged data from NaraaCare when <user_context> (today and "
                "the last 7 days) is not enough: kind 'day' = water, food and sleep totals of one "
                "date; 'period' = averages over the last N days (1-90); 'meals' = the meals and "
                "foods of one date. Dates are YYYY-MM-DD within the last 90 days."
            ),
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "kind": {"type": "string", "enum": ["day", "period", "meals"]},
                    "date": {"type": ["string", "null"]},
                    "days": {"type": ["integer", "null"]},
                },
                "required": ["kind", "date", "days"],
                "additionalProperties": False,
            },
        },
    },
]

# Why a model call failed, for the fallback chain (owner 2026-11-11: when OUR OpenAI account is
# limited, step down to the lower model; when nothing on the account works, the free basic mode).
#   "quota": no credits / spending limit reached on the account -> every OpenAI model is refused.
#   "account": the key is invalid or not allowed -> same.
#   "retry": rate limit, overload, timeout, network, or this model rejected the request -> the
#            lower model has its own limits and may well answer.
_QUOTA_CODES = {"insufficient_quota", "billing_hard_limit_reached", "credit_balance_exhausted"}


def failure_kind(exc: BaseException) -> str:
    """Classify a provider error without logging or reading any message text."""
    code = getattr(exc, "code", None)
    body = getattr(exc, "body", None)
    if isinstance(body, dict):
        code = code or body.get("code") or (body.get("error") or {}).get("code")
    if code in _QUOTA_CODES:
        return "quota"
    if isinstance(exc, openai.AuthenticationError | openai.PermissionDeniedError):
        return "account"
    return "retry"


# OpenAI finish reasons in the service's terms.
_STOP = {"stop": "end_turn", "length": "max_tokens", "tool_calls": "tool_use"}


@dataclass(frozen=True, slots=True)
class Usage:
    """Uncached input, output (incl. reasoning) and cached input tokens of one call."""

    input_tokens: int = 0
    output_tokens: int = 0
    cache_write_tokens: int = 0
    cache_read_tokens: int = 0


@dataclass(frozen=True, slots=True)
class ToolCall:
    id: str
    name: str
    input: Any


@dataclass(slots=True)
class TurnResult:
    stop_reason: str | None
    tool_calls: list[ToolCall] = field(default_factory=list)
    usage: Usage = field(default_factory=Usage)
    # The assistant message, sent back unchanged with the tool results.
    content: Any = None


@dataclass(frozen=True, slots=True)
class TextDelta:
    text: str


@dataclass(frozen=True, slots=True)
class TurnDone:
    result: TurnResult


StreamEvent = TextDelta | TurnDone


class RinModel(Protocol):
    model: str

    def stream_turn(
        self, *, system: str, context: str, messages: Sequence[dict[str, Any]]
    ) -> AsyncIterator[StreamEvent]: ...

    def followup(
        self, result: TurnResult, outputs: Sequence[tuple[str, str]]
    ) -> list[dict[str, Any]]: ...


def usage_of(u: Any) -> Usage:
    """OpenAI usage -> Usage (prompt_tokens includes the cached part)."""
    if u is None:
        return Usage()
    details = getattr(u, "prompt_tokens_details", None)
    cached = (getattr(details, "cached_tokens", 0) or 0) if details is not None else 0
    prompt = u.prompt_tokens or 0
    return Usage(
        input_tokens=max(prompt - cached, 0),
        output_tokens=u.completion_tokens or 0,
        cache_read_tokens=cached,
    )


class OpenAIRinModel:
    def __init__(self, *, api_key: str, model: str, effort: str, max_tokens: int) -> None:
        # 60 s per request, 2 SDK retries (429/5xx/connection errors back off inside the SDK).
        self._client = AsyncOpenAI(api_key=api_key, timeout=60.0, max_retries=2)
        self.model = model
        self._effort = effort
        self._max_tokens = max_tokens

    async def stream_turn(
        self, *, system: str, context: str, messages: Sequence[dict[str, Any]]
    ) -> AsyncIterator[StreamEvent]:
        stream = await self._client.chat.completions.create(
            model=self.model,
            max_completion_tokens=self._max_tokens,
            reasoning_effort=cast("Any", self._effort),
            messages=cast(
                "list[ChatCompletionMessageParam]",
                [
                    {"role": "developer", "content": system},
                    {"role": "developer", "content": context},
                    *messages,
                ],
            ),
            tools=TOOLS,
            store=False,  # no conversation kept on OpenAI's side
            stream=True,
            stream_options={"include_usage": True},
        )
        text: list[str] = []
        calls: dict[int, dict[str, str]] = {}
        finish: str | None = None
        refused = False
        usage = Usage()
        async for chunk in stream:
            if chunk.usage is not None:
                usage = usage_of(chunk.usage)
            for choice in chunk.choices:
                delta = choice.delta
                if delta.content:
                    text.append(delta.content)
                    yield TextDelta(delta.content)
                if getattr(delta, "refusal", None):
                    refused = True
                for tc in delta.tool_calls or []:
                    slot = calls.setdefault(tc.index, {"id": "", "name": "", "arguments": ""})
                    if tc.id:
                        slot["id"] = tc.id
                    if tc.function is not None:
                        slot["name"] += tc.function.name or ""
                        slot["arguments"] += tc.function.arguments or ""
                if choice.finish_reason:
                    finish = choice.finish_reason
        tool_calls = []
        for slot in calls.values():
            try:
                arguments = json.loads(slot["arguments"] or "{}")
            except ValueError:
                arguments = None  # rejected by the service's validation like any bad input
            tool_calls.append(ToolCall(id=slot["id"], name=slot["name"], input=arguments))
        stop = (
            "refusal" if refused or finish == "content_filter" else _STOP.get(finish or "", finish)
        )
        assistant: dict[str, Any] = {"role": "assistant", "content": "".join(text) or None}
        if calls:
            assistant["tool_calls"] = [
                {
                    "id": slot["id"],
                    "type": "function",
                    "function": {"name": slot["name"], "arguments": slot["arguments"] or "{}"},
                }
                for slot in calls.values()
            ]
        yield TurnDone(
            TurnResult(stop_reason=stop, tool_calls=tool_calls, usage=usage, content=assistant)
        )

    def followup(
        self, result: TurnResult, outputs: Sequence[tuple[str, str]]
    ) -> list[dict[str, Any]]:
        return [
            result.content,
            *(
                {"role": "tool", "tool_call_id": call_id, "content": text}
                for call_id, text in outputs
            ),
        ]
