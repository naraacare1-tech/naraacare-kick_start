"""Basic Rin: free answers without any AI model (owner 2026-11-11).

Used when our OpenAI account cannot answer (no credits, spending limit reached, key missing or every
model failing), so the chat never just says "resting". It works only from the user's own context
(``ai.fn_rin_context``: today and the last 7 days) and fixed, reviewed texts:

* "I drank 2 glasses of water" / "I had chai" -> a drink proposal (the normal confirmation card);
* "I ate 2 roti and dal" -> a meal proposal (foods matched in the food database by the service);
* status, water, food / protein, sleep questions -> today's numbers plus a short tip;
* greetings and anything else -> what Rin can do, with examples.

The reply reads like any Rin answer (owner 2026-11-11: no "AI paused" note), and it counts toward
the user's monthly limit like an AI reply of the same size (the service records it).

Pure functions, no I/O: the service turns proposals into pending actions. Text in, plain text out;
nothing here echoes the user's words back except validated food names in the meal proposal.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field
from typing import Any

import regex

MAX_MEAL_ITEMS = 6
MIN_FOOD_NAME = 2
SHORT_GREETING = 40  # "hi" plus a few words; longer messages are real questions


# Volumes for spoken units (doc 06 drink defaults are in ml).
_UNIT_ML = {
    "glass": 250,
    "cup": 150,
    "bottle": 500,
    "mug": 250,
    "l": 1000,
    "litre": 1000,
    "liter": 1000,
    "ml": 1,
}
_NUMBER_WORDS = {
    "a": 1,
    "an": 1,
    "one": 1,
    "ek": 1,
    "two": 2,
    "do": 2,
    "three": 3,
    "teen": 3,
    "four": 4,
    "char": 4,
    "five": 5,
    "paanch": 5,
    "half": 0.5,
    "aadha": 0.5,
}
_DRINKS = {
    "water": "water",
    "pani": "water",
    "paani": "water",
    "tea": "tea",
    "chai": "tea",
    "coffee": "coffee",
    "milk": "milk",
    "doodh": "milk",
    "juice": "juice",
    "coconut water": "coconut_water",
    "nariyal pani": "coconut_water",
    "nariyal paani": "coconut_water",
}

_QUESTION = regex.compile(
    r"\?|^\s*(how|what|which|why|when|should|can|could|is|are|do|does|kya|kitna|kitni|kaise|kab)\b",
    regex.IGNORECASE,
)
# "add / log / track 1 l of water" counts as a log request too (owner 2026-11-11).
_DRINK_VERB = regex.compile(
    r"\b(drank|drink|drunk|had|have had|sipped|piya|pi liya|pee liya|add|added|log|logged|"
    r"track|record|enter)\b",
    regex.I,
)
_EAT_VERB = regex.compile(
    r"\b(ate|eaten|had|have had|khaya|khayi|kha liya|add|added|log|logged|track|record|enter)\b",
    regex.I,
)
_AMOUNT = regex.compile(
    r"\b(?P<n>\d+(?:\.\d+)?|a|an|one|ek|two|do|three|teen|four|char|five|paanch|half|aadha)\s*"
    r"(?P<u>ml|l|litres?|liters?|glass(?:es)?|cups?|bottles?|mugs?)\b",
    regex.IGNORECASE,
)
_GREETING = regex.compile(
    r"^\s*(hi|hello|hey|namaste|namaskar|good (morning|afternoon|evening))\b", regex.I
)
_STATUS = regex.compile(
    r"\b(how am i|how'?s my|my (day|progress|status)|today|summary|check|status|progress|"
    r"update|stats|kaisa|kaise chal)\b",
    regex.I,
)
_WATER = regex.compile(r"\b(water|hydrat\w*|pani|paani|drink)\b", regex.I)
_FOOD = regex.compile(
    r"\b(food|eat|meal|calorie\w*|kcal|protein|carb\w*|fat|diet|khana|nutrition)\b", regex.I
)
_PROTEIN = regex.compile(r"\bprotein\b", regex.I)
_SLEEP = regex.compile(r"\b(sleep|slept|bed ?time|insomnia|neend|sona)\b", regex.I)
_SPLIT = regex.compile(r",|\band\b|\baur\b|\bwith\b|\bplus\b|&", regex.I)
_LEADING_QTY = regex.compile(
    r"^\s*(\d+(?:\.\d+)?|a|an|one|ek|two|do|three|teen|four|five|half)\s+", regex.I
)
_FILLER = regex.compile(
    r"\b(i|just|for|my|some|bowl|bowls|plate|plates|piece|pieces|of|breakfast|lunch|dinner|snack|"
    r"today|now|morning|evening|night|the)\b",
    regex.I,
)


@dataclass(slots=True)
class BasicReply:
    text: str
    drink: dict[str, Any] | None = None  # {"drink": code, "volume_ml": int}
    meal_items: list[dict[str, Any]] = field(default_factory=list)  # food_name, quantity, unit


def _num(word: str) -> float:
    try:
        return float(word)
    except ValueError:
        return float(_NUMBER_WORDS.get(word.lower(), 1))


def _drink_code(text: str) -> str | None:
    low = text.lower()
    for name in sorted(_DRINKS, key=len, reverse=True):  # "coconut water" before "water"
        if regex.search(rf"\b{regex.escape(name)}\b", low):
            return _DRINKS[name]
    return None


def _drink(text: str) -> dict[str, Any] | None:
    if not _DRINK_VERB.search(text):
        return None
    code = _drink_code(text)
    if code is None:
        return None
    match = _AMOUNT.search(text)
    if match:
        unit = match["u"].lower().rstrip("s").replace("glasse", "glass")
        unit = "litre" if unit in {"litre", "liter"} else unit
        ml = _num(match["n"]) * _UNIT_ML.get(unit, 250)
    else:
        ml = 150 if code in {"tea", "coffee"} else 250
    return {"drink": code, "volume_ml": int(min(max(round(ml), 50), 2000))}


def _meal(text: str) -> list[dict[str, Any]]:
    verb = _EAT_VERB.search(text)
    if not verb:
        return []
    items: list[dict[str, Any]] = []
    for raw in _SPLIT.split(text[verb.end() :])[:MAX_MEAL_ITEMS]:
        qty, part = 1.0, raw
        lead = _LEADING_QTY.match(part)
        if lead:
            qty = _num(lead.group(1))
            part = part[lead.end() :]
        name = " ".join(_FILLER.sub(" ", part).split())
        name = regex.sub(r"[^\p{L}\p{N} '-]", "", name).strip(" '-")[:64]
        if len(name) >= MIN_FOOD_NAME:
            items.append({"food_name": name, "quantity": min(max(qty, 0.5), 20), "unit": "serving"})
    return items


def _get(context: dict[str, Any], *path: str) -> Any:
    value: Any = context
    for key in path:
        value = value.get(key) if isinstance(value, dict) else None
    return value


def _hm(minutes: float) -> str:
    m = round(minutes)
    return f"{m // 60}h {m % 60:02d}m"


def _water_line(context: dict[str, Any]) -> str:
    consumed, goal = (
        _get(context, "water_today", "consumed_ml"),
        _get(context, "water_today", "goal_ml"),
    )
    if not consumed:
        return "You haven't logged any water today yet."
    if goal:
        left = max(0, goal - consumed)
        return f"You've had {consumed / 1000:.1f} L of your {goal / 1000:.1f} L water goal" + (
            " - goal reached, well done!" if left == 0 else f"; about {left / 1000:.1f} L to go."
        )
    return f"You've had {consumed / 1000:.1f} L of water today."


def _food_line(context: dict[str, Any]) -> str:
    kcal = _get(context, "food_today", "kcal")
    if not kcal:
        return "You haven't logged a meal today yet."
    allowance = _get(context, "food_today", "allowance_kcal")
    protein = _get(context, "food_today", "protein_g")
    line = f"You've eaten {kcal:,} kcal" + (
        f" of your {allowance:,} kcal allowance" if allowance else ""
    )
    return line + (f", with {protein} g protein." if protein is not None else ".")


def _sleep_line(context: dict[str, Any]) -> str:
    counted = _get(context, "sleep_today", "counted_min")
    if not counted:
        avg = _get(context, "last_7_days", "avg_sleep_min")
        return (
            f"No sleep logged for last night; your 7-day average is {_hm(avg)}."
            if avg
            else "No sleep logged yet."
        )
    goal = _get(context, "profile", "sleep_goal_min")
    score = _get(context, "sleep_today", "score_pct")
    line = f"You slept {_hm(counted)}" + (f" against a {_hm(goal)} goal" if goal else "")
    return line + (f" (sleep score {score}%)." if score is not None else ".")


WATER_TIP = "Tip: keep a bottle in sight and have a glass with every meal and after waking up."
PROTEIN_TIP = (
    "Good protein options: dal, chana, rajma, paneer, curd, eggs, sprouts, soya chunks or chicken. "
    "Add one to each meal."
)
FOOD_TIP = (
    "Tip: fill half your plate with vegetables, a quarter with protein and a quarter with grains."
)
SLEEP_TIP = (
    "Tips: keep the same bedtime every day, avoid screens and tea or coffee late in the evening, "
    "and keep your room dark and cool."
)
HELP_TEXT = (
    "I can help with water, food and sleep. Try: 'How am I doing today?', 'I drank 2 glasses of "
    "water', 'I ate 2 roti and dal' or 'How can I sleep better?'"
)


def answer(prompt: str, context: dict[str, Any]) -> BasicReply:
    """Basic Rin's reply to ``prompt`` from the user's own ``context`` (no AI)."""
    text = unicodedata.normalize("NFKC", prompt)
    asking = bool(_QUESTION.search(text))
    if not asking:
        drink = _drink(text)
        if drink is not None:
            return BasicReply(
                "Here's the drink I understood. Check it and tap Add to log it.", drink=drink
            )
        if not _drink_code(text):
            items = _meal(text)
            if items:
                return BasicReply(
                    "Here's the meal I understood. Check it and tap Add to log it.",
                    meal_items=items,
                )
    if _GREETING.search(text) and len(text) < SHORT_GREETING:
        body = f"Hi! I'm Rin. {HELP_TEXT}"
    elif _STATUS.search(text):
        body = " ".join([_water_line(context), _food_line(context), _sleep_line(context)])
    elif _SLEEP.search(text):
        body = f"{_sleep_line(context)} {SLEEP_TIP}"
    elif _PROTEIN.search(text):
        body = f"{_food_line(context)} {PROTEIN_TIP}"
    elif _FOOD.search(text):
        body = f"{_food_line(context)} {FOOD_TIP}"
    elif _WATER.search(text):
        body = f"{_water_line(context)} {WATER_TIP}"
    else:
        body = HELP_TEXT
    return BasicReply(body)
