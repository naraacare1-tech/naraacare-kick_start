"""Rin AI requests (doc 04 section 2.10). Prompts are SafeChatMessage (plain text, 2000 max);
edited meal items reuse the meal item schema (S08). No user id from the client."""

from __future__ import annotations

from typing import Annotated

from pydantic import Field

from app.core.security.validators import SafeChatMessage
from app.schemas.common import JsonUUID
from app.schemas.nutrition import MealItemIn, _Model


class RinPrompt(_Model):
    client_message_id: JsonUUID
    content: SafeChatMessage


class RinActionAccept(_Model):
    items: Annotated[list[MealItemIn], Field(min_length=1, max_length=30)] | None = None
