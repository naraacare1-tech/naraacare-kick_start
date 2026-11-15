"""Stand-ins for outside services, shared by the test packages."""

from __future__ import annotations

from collections.abc import AsyncIterator, Sequence
from dataclasses import dataclass, field
from typing import Any

from app.domain.ai.rin_model import StreamEvent, TextDelta, ToolCall, TurnDone, TurnResult, Usage


@dataclass
class ScriptedTurn:
    """One model turn: text chunks, then optional tool calls and a stop reason."""

    text: Sequence[str] = ("Sure.",)
    tool_calls: Sequence[ToolCall] = ()
    stop_reason: str = "end_turn"
    usage: Usage = field(default_factory=lambda: Usage(input_tokens=100, output_tokens=20))
    error: Exception | None = None  # raised after the text (a mid-stream failure)


@dataclass
class FakeRinModel:
    """A RinModel that replays scripted turns (the last one repeats) and records each call."""

    turns: list[ScriptedTurn] = field(default_factory=lambda: [ScriptedTurn()])
    model: str = "gpt-test"
    calls: list[dict[str, Any]] = field(default_factory=list)

    async def stream_turn(
        self, *, system: str, context: str, messages: Sequence[dict[str, Any]]
    ) -> AsyncIterator[StreamEvent]:
        self.calls.append({"system": system, "context": context, "messages": list(messages)})
        turn = self.turns[min(len(self.calls) - 1, len(self.turns) - 1)]
        for chunk in turn.text:
            yield TextDelta(chunk)
        if turn.error is not None:
            raise turn.error
        yield TurnDone(
            TurnResult(
                stop_reason=turn.stop_reason,
                tool_calls=list(turn.tool_calls),
                usage=turn.usage,
                content={"role": "assistant", "content": "".join(turn.text) or None},
            )
        )

    def followup(
        self, result: TurnResult, outputs: Sequence[tuple[str, str]]
    ) -> list[dict[str, Any]]:
        return [
            result.content,
            *({"role": "tool", "tool_call_id": i, "content": text} for i, text in outputs),
        ]
