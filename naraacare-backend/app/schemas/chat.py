"""Circle chat and realtime frames (doc 04 section 2.9). Message bodies are SafeChatMessage (plain
text and emoji, no markup); mentions are member user ids picked in the app, never parsed from the
text. WebSocket client frames are small JSON objects of a fixed shape; anything else is ignored."""

from __future__ import annotations

from typing import Annotated, Literal

from pydantic import AfterValidator, Field

from app.core.security.validators import SafeChatMessage
from app.schemas.common import JsonUUID
from app.schemas.nutrition import _Model
from app.schemas.social import _unique


class MessageCreate(_Model):
    client_message_id: JsonUUID
    body: SafeChatMessage
    mention_user_ids: Annotated[
        list[JsonUUID], Field(max_length=20, default_factory=list), AfterValidator(_unique)
    ]


class PingFrame(_Model):
    type: Literal["ping"]


class TypingFrame(_Model):
    type: Literal["typing"]
    circle_id: JsonUUID


ClientFrame = Annotated[PingFrame | TypingFrame, Field(discriminator="type")]
