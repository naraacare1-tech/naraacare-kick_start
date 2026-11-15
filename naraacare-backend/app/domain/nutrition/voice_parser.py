"""Voice meal transcript -> food phrases with quantities and units (OQ-43).

The app turns speech into text on the device (``speech_to_text``, en-IN), so no audio reaches the
server. The transcript (already a validated ``SafeText(300)``) is split here into parts such as
"do roti aur ek katori dal" -> [(2, None, None, "roti"), (1, "katori", None, "dal")]; the database
then matches each food phrase to a food by name or Hinglish/Hindi alias
(``nutrition.fn_alias_match``) and the user confirms or edits the result before saving.

Pure functions, no I/O. Quantities are snapped to the meal rules (0.25 steps, 0.25..20).
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal

MAX_PARTS = 20
MAX_PHRASE = 60

# "aur" / "and" / "with" / "plus" / punctuation separate foods.
_SEPARATORS = re.compile(
    r"\s*(?:,|;|\.(?=\s|$)|&|\+|\band\b|\baur\b|\bor\b|\bwith\b|\bplus\b|\bn\b)\s*"
)
_NUMBER = re.compile(r"^\d{1,2}(?:\.\d{1,2})?$")
_FRACTION = re.compile(r"^(\d)/(\d)$")

QUANTITY_WORDS: dict[str, Decimal] = {
    # English
    "a": Decimal(1),
    "an": Decimal(1),
    "one": Decimal(1),
    "two": Decimal(2),
    "three": Decimal(3),
    "four": Decimal(4),
    "five": Decimal(5),
    "six": Decimal(6),
    "half": Decimal("0.5"),
    "quarter": Decimal("0.25"),
    # Hindi / Hinglish
    "ek": Decimal(1),
    "do": Decimal(2),
    "teen": Decimal(3),
    "char": Decimal(4),
    "chaar": Decimal(4),
    "paanch": Decimal(5),
    "panch": Decimal(5),
    "chhe": Decimal(6),
    "aadha": Decimal("0.5"),
    "adha": Decimal("0.5"),
    "aadhi": Decimal("0.5"),
    "dedh": Decimal("1.5"),
    "dhai": Decimal("2.5"),
    "sawa": Decimal("1.25"),
    "paav": Decimal("0.25"),
}

# Spoken unit -> ref.unit code.
UNIT_WORDS: dict[str, str] = {
    "katori": "katori",
    "katoris": "katori",
    "bowl": "bowl",
    "bowls": "bowl",
    "cup": "cup",
    "cups": "cup",
    "glass": "glass",
    "glasses": "glass",
    "gilas": "glass",
    "mug": "mug",
    "mugs": "mug",
    "cutting": "cutting",
    "piece": "piece",
    "pieces": "piece",
    "pcs": "piece",
    "plate": "plate",
    "plates": "plate",
    "tbsp": "tbsp",
    "tablespoon": "tbsp",
    "tablespoons": "tbsp",
    "chammach": "tbsp",
    "chamach": "tbsp",
    "spoon": "tbsp",
    "spoons": "tbsp",
    "tsp": "tsp",
    "teaspoon": "tsp",
    "teaspoons": "tsp",
    "serving": "serving",
    "servings": "serving",
}

# Size words -> unit_size. "half"/"full" only describe plates ("half plate rice").
SIZE_WORDS: dict[str, str] = {
    "small": "small",
    "chhota": "small",
    "chhoti": "small",
    "chota": "small",
    "choti": "small",
    "medium": "medium",
    "large": "large",
    "big": "large",
    "bada": "large",
    "badi": "large",
    "full": "full",
    "poora": "full",
    "puri": "full",
}

FILLER_WORDS = frozenset(
    {
        "of",
        "ki",
        "ka",
        "ke",
        "khaya",
        "khayi",
        "khaye",
        "kha",
        "liya",
        "li",
        "i",
        "had",
        "ate",
        "maine",
        "mene",
        "some",
        "thoda",
        "thodi",
        "the",
    }
)


@dataclass(frozen=True, slots=True)
class ParsedPart:
    quantity: Decimal
    unit_code: str | None
    unit_size: str | None
    phrase: str


def snap_quantity(value: Decimal) -> Decimal:
    """Nearest 0.25 within 0.25..20 (the meal-item rules)."""
    quarters = (value * 4).quantize(Decimal(1), rounding=ROUND_HALF_UP)
    snapped = quarters / 4
    return min(max(snapped, Decimal("0.25")), Decimal(20))


def _quantity(token: str) -> Decimal | None:
    if token in QUANTITY_WORDS:
        return QUANTITY_WORDS[token]
    if _NUMBER.match(token):
        return Decimal(token)
    fraction = _FRACTION.match(token)
    if fraction and int(fraction.group(2)) != 0:
        return Decimal(int(fraction.group(1))) / Decimal(int(fraction.group(2)))
    return None


def parse_part(text: str) -> ParsedPart | None:
    """One food mention: optional quantity, size and unit words around the food phrase."""
    quantity: Decimal | None = None
    unit: str | None = None
    size: str | None = None
    words: list[str] = []
    tokens = text.split()
    for i, token in enumerate(tokens):
        if quantity is None and not words and (q := _quantity(token)) is not None:
            # "half plate" is a plate size; "half katori" is a quantity.
            nxt = tokens[i + 1] if i + 1 < len(tokens) else ""
            if token in {"half", "aadha", "adha", "aadhi"} and UNIT_WORDS.get(nxt) == "plate":
                size = "half"
                continue
            quantity = q
        elif token in UNIT_WORDS and unit is None:
            unit = UNIT_WORDS[token]
        elif token in SIZE_WORDS and size is None and not words:
            size = SIZE_WORDS[token]
        elif token in FILLER_WORDS:
            continue
        else:
            words.append(token)
    phrase = " ".join(words)[:MAX_PHRASE].strip()
    if not phrase:
        return None
    if size == "full" and unit != "plate":
        size = None
    return ParsedPart(snap_quantity(quantity or Decimal(1)), unit, size, phrase)


def parse_transcript(transcript: str) -> list[ParsedPart]:
    """Lower-case, split into food mentions, keep at most ``MAX_PARTS``."""
    text = re.sub(r"[^\w\s.,;&+/]", " ", transcript.lower())
    parts = [p for p in _SEPARATORS.split(text) if p and p.strip()]
    parsed = [part for p in parts if (part := parse_part(p.strip())) is not None]
    return parsed[:MAX_PARTS]
