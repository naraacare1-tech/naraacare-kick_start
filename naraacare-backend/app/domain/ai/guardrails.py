"""Rin AI guardrails (doc 06 section 8, doc 07 T20).

* ``emergency_reply``: symptoms that may be an emergency (chest pain, fainting, self-harm, severe
  dehydration signs), in English and Hinglish, get a fixed reply with India emergency numbers and
  NO model call. Matching is deliberately broad: a false positive costs one safe message.
* ``to_plain_text``: model output becomes plain text before it is streamed, stored or shown:
  HTML-like tags, markdown markers, template and encoding sequences and script schemes are removed,
  so the text passes the same rules as user input (``common.safe_text``). If anything unsafe is
  still left, the whole reply is replaced by a fixed message.
"""

from __future__ import annotations

import unicodedata

import regex

from app.core.security.validators import contains_unsafe_content

MAX_REPLY_CHARS = 8000

EMERGENCY_REPLY = (
    "I'm concerned about what you've described. This could need urgent care. "
    "Please call 112 (emergency) or 108 (ambulance) now, or go to the nearest hospital. "
    "If you are thinking about harming yourself, please call Tele-MANAS on 14416, any time. "
    "I can't give medical advice, but you don't have to handle this alone."
)

FALLBACK_REPLY = "Sorry, I couldn't answer that. Please try asking in a different way."
REFUSAL_REPLY = (
    "I can't help with that one. I can help with water, meals, sleep and healthy habits."
)
UNAVAILABLE_REPLY = "Rin is resting right now. Please try again soon."
OFF_TOPIC_REPLY = (
    "I'm Rin, your NaraaCare companion, so I can only help with water, food and nutrition, sleep "
    "and healthy daily habits. Ask me about your meals, hydration or sleep!"
)

# Clearly off-topic requests answered without calling the model (owner 2026-11-08: Rin stays on
# water, food/nutrition and sleep; saves the user's monthly AI budget). Only unmistakable
# programming / tech-help requests are caught here; anything subtler is refused by the prompt.
_LANGUAGES = (
    r"python|javascript|typescript|java|kotlin|swift|golang|rust|php|ruby|perl|c\+\+|c#|"
    r"html|css|sql|bash|powershell|react|angular|vue|flutter|dart|django|flask|node\.?js|"
    r"spring boot|laravel|android studio|xcode"
)
_CODE_WORDS = (
    r"code|coding|program|programming|script|function|method|class|bug|debug|error|exception|"
    r"syntax|compile|compiler|library|framework|api|endpoint|loop|array|variable|query|regex|"
    r"algorithm|install|deploy|repo|github"
)
_OFF_TOPIC = regex.compile(
    r"```"
    r"|\b(write|give|generate|create|fix|debug|explain|solve)\b.{0,30}\b(code|program|script|"
    r"function|algorithm|regex|sql query)\b"
    rf"|\b({_LANGUAGES})\b.{{0,60}}\b({_CODE_WORDS})\b"
    rf"|\b({_CODE_WORDS})\b.{{0,60}}\b({_LANGUAGES})\b"
    r"|\b(leetcode|hackerrank|stack ?trace|segmentation fault|null ?pointer|time complexity)\b"
    r"|\bdef \w+\(|\bfunction\s*\w*\s*\(|#include\b|public static void|console\.log|"
    r"\bselect\b.{1,80}\bfrom\b.{1,80}\bwhere\b",
    regex.IGNORECASE | regex.DOTALL,
)

# Signals of a possible emergency (doc 06 section 8). Word-ish boundaries; case-insensitive.
_EMERGENCY = regex.compile(
    r"\b("
    r"chest pain|pain in (my )?chest|heart attack|can'?t breathe|cannot breathe"
    r"|short(ness)? of breath"
    r"|faint(ed|ing)?|pass(ed)? out|unconscious|seizure|stroke"
    r"|suicid\w*|kill (my ?self|myself)|end (my|it all)|want to die|self[- ]?harm|hurt myself"
    r"|overdose|severe(ly)? dehydrat\w*|no urine|not peed"
    r"|seene (me|mein|mai) dard|saans (nahi|nhi|lene me)|behosh|chakkar aa(ya|ke gir)"
    r"|marna chah\w*|khud ?kushi|jaan de\w*|khud ko (nuksan|hurt)"
    r")\b",
    regex.IGNORECASE,
)

_TAG = regex.compile(r"<[^<>\n]{0,300}>")
_ANGLE = regex.compile(r"[<>\uFF1C\uFF1E\uFE64\uFE65\u2039\u203A]")
_MD_MARKERS = regex.compile(r"(\*\*|__|`+|~~)")
_MD_HEADING = regex.compile(r"(?m)^\s{0,3}#{1,6}\s*")
_MD_BULLET = regex.compile(r"(?m)^\s*[*+]\s+")
_MD_LINK = regex.compile(r"\[([^\]\n]{1,200})\]\([^)\n]{0,500}\)")
_TEMPLATES = regex.compile(r"\{\{|\}\}|\$\{|<%|%>|#\{")
_ENTITY = regex.compile(r"&(#x?[0-9a-f]+;?|[a-z]+;)", regex.IGNORECASE)
_PERCENT_HEX = regex.compile(r"%(?=[0-9a-f]{2})", regex.IGNORECASE)
_ESCAPES = regex.compile(r"\\(?=u[0-9a-f]{4}|x[0-9a-f]{2})", regex.IGNORECASE)
_SCHEME = regex.compile(r"(java|vb|live)\s*script\s*:|data\s*:\s*[a-z]+/", regex.IGNORECASE)
_HANDLER = regex.compile(r"(^|[^a-z0-9_])(on[a-z]+)\s*=", regex.IGNORECASE)
_CSS = regex.compile(r"(expression|url)\s*\(|@import", regex.IGNORECASE)
_CONTROL = regex.compile(r"[\x00-\x09\x0B-\x1F\x7F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]")
_SPACES = regex.compile(r"[ \t]{2,}")
_BLANKS = regex.compile(r"\n{3,}")


def emergency_reply(prompt: str) -> str | None:
    """The fixed emergency reply when the prompt suggests an emergency, else None."""
    text = unicodedata.normalize("NFKC", prompt)
    return EMERGENCY_REPLY if _EMERGENCY.search(text) else None


def off_topic_reply(prompt: str) -> str | None:
    """The fixed scope reply for an unmistakable programming / tech request, else None."""
    text = unicodedata.normalize("NFKC", prompt)
    return OFF_TOPIC_REPLY if _OFF_TOPIC.search(text) else None


def strip_delta(text: str) -> str:
    """Cheap per-chunk cleanup while streaming (the final text is cleaned again in full)."""
    return _CONTROL.sub("", _ANGLE.sub("", _MD_MARKERS.sub("", text)))


def to_plain_text(text: str) -> str:
    """Model output as plain text that passes the input rules, or the fallback reply."""
    t = unicodedata.normalize("NFKC", text)
    t = _TAG.sub("", t)
    t = _ANGLE.sub("", t)
    t = _MD_LINK.sub(r"\1", t)
    t = _MD_HEADING.sub("", t)
    t = _MD_BULLET.sub("• ", t)
    t = _MD_MARKERS.sub("", t)
    t = _TEMPLATES.sub("", t)
    t = _ENTITY.sub("", t)
    t = _PERCENT_HEX.sub("% ", t)
    t = _ESCAPES.sub("", t)
    t = _SCHEME.sub("", t)
    t = _HANDLER.sub(lambda m: f"{m.group(1)}{m.group(2)} ", t)
    t = _CSS.sub("", t)
    t = _CONTROL.sub("", t.replace("\r\n", "\n"))
    t = _BLANKS.sub("\n\n", _SPACES.sub(" ", t)).strip()
    if len(t) > MAX_REPLY_CHARS:
        t = t[: MAX_REPLY_CHARS - 1].rstrip() + "…"
    if not t or contains_unsafe_content(t, multiline=True, allow_emoji_zwj=True):
        return FALLBACK_REPLY
    return t
