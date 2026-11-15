"""Safe* input types: the single source of input rules (doc 04 §1.2, doc 07 §4.2).

Every string the API accepts (body, query, path, data headers) uses one of these types. Input that
contains scripting or markup is REJECTED, never stripped or escaped. Pipeline per value:

1. R5 on the raw input: control characters, NUL, zero-width and bidi overrides (newlines only in
   multi-line types).
2. Unicode NFKC (folds full-width angle brackets into ``<``/``>``, ligatures, compatibility digits).
3. R6/R7/R8 on the raw and the normalised input: HTML entities, %-encoding, ``\\uXXXX``/``\\xXX``.
4. Inspection forms: the normalised value and up to 3 rounds of URL- and entity-decoding of it.
   R1-R4 and R9 must match none of them; R3 is also checked with all whitespace removed
   (catches ``java script:``).
5. The per-type allow-list (regex with Unicode properties, so Indic scripts pass).
6. Length on the normalised value (the declared max length is also enforced on the raw value and
   published in OpenAPI).

The stored value is the NFKC form of the input, trimmed for single-line types. Error messages are
generic and never contain the input. Mirrors: ``common.safe_text`` (database) and
``input_validators.dart`` (mobile); all three are tested with the same payload list.
"""

from __future__ import annotations

import html
import unicodedata
import urllib.parse
import zoneinfo
from dataclasses import dataclass
from enum import StrEnum
from functools import cache
from typing import Annotated, Any

import regex
from email_validator import EmailNotValidError, validate_email
from pydantic import GetCoreSchemaHandler, GetJsonSchemaHandler
from pydantic.json_schema import JsonSchemaValue
from pydantic_core import PydanticCustomError, core_schema

UNSAFE_INPUT = "unsafe_input"
INVALID_FORMAT = "invalid_format"
_UNSAFE_MESSAGE = "Input contains characters that are not allowed"
_FORMAT_MESSAGE = "Input is not in the expected format"

# Character classes are built from code points: source files never contain invisible characters.
_CONTROL = "".join(
    [chr(c) for c in range(0x00, 0x09)]
    + [chr(0x0B), chr(0x0C)]
    + [chr(c) for c in range(0x0E, 0x20)]
    + [chr(0x7F)]
)
_INVISIBLE = "".join(
    [chr(c) for c in range(0x200B, 0x2010)]  # zero-width space/joiners, LRM, RLM
    + [chr(c) for c in range(0x202A, 0x202F)]  # bidi embeddings and overrides
    + [chr(c) for c in range(0x2066, 0x206A)]  # bidi isolates
    + [chr(0xFEFF)]  # BOM / zero-width no-break space
)
ZWJ = chr(0x200D)
_VS16 = chr(0xFE0F)


def _cls(chars: str) -> str:
    return "[" + "".join(regex.escape(c) for c in chars) + "]"


R5 = regex.compile(_cls(_CONTROL + _INVISIBLE))
R5_SINGLE_LINE = regex.compile(_cls(_CONTROL + _INVISIBLE + "\t\n\r"))
R5_MULTI_LINE = regex.compile(_cls(_CONTROL + _INVISIBLE + "\t"))
R6 = regex.compile(r"(?i)&#x?[0-9a-f]+;?|&[a-z]+;")
R7 = regex.compile(r"(?i)%[0-9a-f]{2}")
R8 = regex.compile(r"(?i)\\u[0-9a-f]{4}|\\x[0-9a-f]{2}")
R3 = (
    regex.compile(r"(?i)(javascript|vbscript|livescript)\s*:"),  # script schemes
    regex.compile(r"(?i)data\s*:\s*[a-z]+/[a-z0-9.+-]+"),  # data URIs
)
INSPECTION_PATTERNS = (
    regex.compile(r"[<>]"),  # R1 tags
    regex.compile(r"(?i)(^|[^a-z])on[a-z]+\s*="),  # R2 event handlers
    *R3,
    regex.compile(r"\{\{|\}\}|\$\{|<%|%>|#\{"),  # R4 templates
    regex.compile(r"(?i)expression\s*\(|url\s*\(|@import"),  # R9 CSS
)
_WHITESPACE = regex.compile(r"[\s" + regex.escape(_CONTROL) + "]+")
_DECODE_ROUNDS = 3


class Kind(StrEnum):  # values are type labels, not secrets
    NAME = "name"
    USERNAME = "username"
    EMAIL = "email"
    PASSWORD = "password"  # noqa: S105  # nosec B105
    NEW_PASSWORD = "new_password"  # noqa: S105  # nosec B105
    OTP = "otp"
    SHORT_TEXT = "short_text"
    TEXT = "text"
    CHAT = "chat"
    SEARCH = "search"
    OPAQUE_TOKEN = "opaque_token"  # noqa: S105  # nosec B105
    REFERRAL_CODE = "referral_code"
    BARCODE = "barcode"
    TIMEZONE = "timezone"
    LOCALE = "locale"
    FILE_NAME = "file_name"
    APP_VERSION = "app_version"
    DEVICE_TOKEN = "device_token"  # noqa: S105  # nosec B105
    CODE = "code"  # reference codes, same format as the database domain common.code
    YEAR_MONTH = "year_month"  # report / streak month, YYYY-MM (S14)


SUPPORTED_LOCALES = frozenset({"en", "en-IN", "hi", "hi-IN"})  # OQ-52: English first, Hindi ready

_APOSTROPHE = chr(0x2019)  # iOS/Android "smart" apostrophe in names like D'Souza
_SHORT_TEXT_CHARS = r"\p{L}\p{M}\p{N} .,'\-()&/+%" + _APOSTROPHE
_TEXT_CHARS = _SHORT_TEXT_CHARS + r"!?:;\"#@\n\r"
_EMOJI = r"\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Regional_Indicator}" + ZWJ + _VS16
_ALLOW: dict[Kind, regex.Pattern[str]] = {
    Kind.NAME: regex.compile(r"^[\p{L}\p{M} .'\-" + _APOSTROPHE + r"]+$"),
    Kind.USERNAME: regex.compile(r"^[a-z0-9](?:[a-z0-9._]{1,28})[a-z0-9]$"),
    Kind.OTP: regex.compile(r"^[0-9]{6}$"),
    Kind.SHORT_TEXT: regex.compile("^[" + _SHORT_TEXT_CHARS + "]+$"),
    Kind.TEXT: regex.compile("^[" + _TEXT_CHARS + "]+$"),
    Kind.CHAT: regex.compile("^[" + _TEXT_CHARS + _EMOJI + "]+$"),
    Kind.SEARCH: regex.compile(r"^[\p{L}\p{M}\p{N} .'\-&@_]+$"),
    Kind.OPAQUE_TOKEN: regex.compile(r"^[A-Za-z0-9._~+/=-]+$"),
    Kind.REFERRAL_CODE: regex.compile(r"^[A-Z0-9]{6,12}$"),
    Kind.BARCODE: regex.compile(r"^[0-9]{8}$|^[0-9]{12,14}$"),
    Kind.LOCALE: regex.compile(r"^[a-z]{2}(-[A-Z]{2})?$"),
    Kind.FILE_NAME: regex.compile(r"^[A-Za-z0-9 _.\-]{1,95}\.(png|jpg|jpeg)$"),
    Kind.APP_VERSION: regex.compile(r"^[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}(\+[0-9]{1,9})?$"),
    Kind.DEVICE_TOKEN: regex.compile(r"^[A-Za-z0-9:_\-]+$"),
    Kind.CODE: regex.compile(r"^[a-z][a-z0-9_.]{0,62}$"),
    Kind.YEAR_MONTH: regex.compile(r"^20[2-9][0-9]-(0[1-9]|1[0-2])$"),
}
_HAS_LETTER = regex.compile(r"\p{L}")
_USERNAME_REPEAT = regex.compile(r"[._]{2}")
_PASSWORD_UPPER = regex.compile(r"\p{Lu}")
_PASSWORD_DIGIT = regex.compile(r"\p{Nd}")
_ZWJ_IN_EMOJI = regex.compile(
    r"(?<=[\p{Extended_Pictographic}\p{Emoji_Modifier}"
    + _VS16
    + "])"
    + ZWJ
    + r"(?=\p{Extended_Pictographic})"
)
_MULTI_LINE = frozenset({Kind.TEXT, Kind.CHAT})
_KEEP_SURROUNDING_SPACE = frozenset({Kind.PASSWORD, Kind.NEW_PASSWORD})


def _unsafe() -> PydanticCustomError:
    return PydanticCustomError(UNSAFE_INPUT, _UNSAFE_MESSAGE)


def _bad_format() -> PydanticCustomError:
    return PydanticCustomError(INVALID_FORMAT, _FORMAT_MESSAGE)


def _decoded_forms(value: str) -> list[str]:
    """value plus up to 3 rounds of URL- and HTML-entity-decoding (inspection only)."""
    forms = [value]
    current = value
    for _ in range(_DECODE_ROUNDS):
        decoded = html.unescape(urllib.parse.unquote(current))
        if decoded == current:
            break
        forms.append(decoded)
        current = decoded
    return forms


def contains_unsafe_content(
    raw: str, *, multiline: bool = False, allow_emoji_zwj: bool = False
) -> bool:
    """True when raw matches any reject pattern R1-R9 in any inspected form (doc 07 §4.2)."""
    candidate = _ZWJ_IN_EMOJI.sub("", raw) if allow_emoji_zwj else raw
    r5 = R5_MULTI_LINE if multiline else R5_SINGLE_LINE
    if r5.search(candidate):
        return True
    normalised = unicodedata.normalize("NFKC", raw)
    for form in (raw, normalised):
        if R6.search(form) or R7.search(form) or R8.search(form):
            return True
    for form in _decoded_forms(normalised):
        if any(p.search(form) for p in INSPECTION_PATTERNS):
            return True
        # R3b: schemes split by whitespace/control characters ("java script:", java+TAB+script:).
        stripped = _WHITESPACE.sub("", form)
        if any(p.search(stripped) for p in R3):
            return True
        if form is not normalised and R5.search(form):
            return True
    return False


@cache
def _timezones() -> frozenset[str]:
    return frozenset(zoneinfo.available_timezones())


def _gtin_ok(digits: str) -> bool:
    body, check = digits[:-1], int(digits[-1])
    total = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


def _check_email(value: str) -> str:
    try:
        result = validate_email(value, check_deliverability=False, allow_smtputf8=False)
    except EmailNotValidError:
        raise _bad_format() from None
    return result.normalized.lower()


def _check_allow_list(kind: Kind, value: str) -> str:  # noqa: PLR0911, PLR0912 - one branch per type
    match kind:
        case Kind.EMAIL:
            return _check_email(value)
        case Kind.USERNAME:
            value = value.lower()
            if not _ALLOW[kind].match(value) or _USERNAME_REPEAT.search(value):
                raise _bad_format()
            return value
        case Kind.REFERRAL_CODE:
            value = value.upper()
        case Kind.TIMEZONE:
            if value not in _timezones():
                raise _bad_format()
            return value
        case Kind.LOCALE:
            if not _ALLOW[kind].match(value) or value not in SUPPORTED_LOCALES:
                raise _bad_format()
            return value
        case Kind.PASSWORD:
            return value
        case Kind.NEW_PASSWORD:
            if not (_PASSWORD_UPPER.search(value) and _PASSWORD_DIGIT.search(value)):
                raise PydanticCustomError(
                    "password_weak", "Password does not meet the requirements"
                )
            return value
        case Kind.BARCODE:
            if not _ALLOW[kind].match(value) or not _gtin_ok(value):
                raise _bad_format()
            return value
        case Kind.FILE_NAME:
            if ".." in value:
                raise _unsafe()
        case _:
            pass
    if not _ALLOW[kind].match(value):
        raise _bad_format()
    if kind is Kind.NAME and not _HAS_LETTER.search(value):
        raise _bad_format()
    return value


@dataclass(frozen=True, slots=True)
class SafeString:
    """Pydantic metadata for ``Annotated[str, SafeString(...)]`` (use the aliases below)."""

    kind: Kind
    max_length: int
    min_length: int = 1

    def validate(self, raw: str) -> str:
        multiline = self.kind in _MULTI_LINE
        if contains_unsafe_content(
            raw, multiline=multiline, allow_emoji_zwj=self.kind is Kind.CHAT
        ):
            raise _unsafe()
        value = unicodedata.normalize("NFKC", raw)
        if self.kind not in _KEEP_SURROUNDING_SPACE:
            value = value.strip()
        if not self.min_length <= len(value) <= self.max_length:
            raise PydanticCustomError("string_length", "Input length is not allowed")
        return _check_allow_list(self.kind, value)

    def __get_pydantic_core_schema__(
        self, source: type[Any], handler: GetCoreSchemaHandler
    ) -> core_schema.CoreSchema:
        # Length is checked on the raw value first (stops oversized input before any regex runs,
        # and publishes maxLength/minLength in OpenAPI), then again on the normalised value.
        return core_schema.no_info_after_validator_function(
            self.validate,
            core_schema.str_schema(
                strict=True, max_length=self.max_length, min_length=self.min_length
            ),
        )

    def __get_pydantic_json_schema__(
        self, schema: core_schema.CoreSchema, handler: GetJsonSchemaHandler
    ) -> JsonSchemaValue:
        # x-safe-kind marks every validated string in OpenAPI: the payload sweep uses it to build
        # valid requests, and tests fail if any string field in the API lacks it (a bare str).
        json_schema = handler(schema)
        json_schema["x-safe-kind"] = self.kind.value
        return json_schema


def safe(kind: Kind, max_length: int, min_length: int = 1) -> SafeString:
    return SafeString(kind=kind, max_length=max_length, min_length=min_length)


# --- Types (doc 04 §1.2). Parameterised types get one alias per size so mypy and Semgrep see a
# named Safe* type at every use site; add an alias here when a new size is needed.
SafeName = Annotated[str, safe(Kind.NAME, 100)]
SafeUsername = Annotated[str, safe(Kind.USERNAME, 30, 3)]
SafeEmail = Annotated[str, safe(Kind.EMAIL, 254, 3)]
SafePassword = Annotated[str, safe(Kind.PASSWORD, 128, 8)]
SafeNewPassword = Annotated[str, safe(Kind.NEW_PASSWORD, 128, 8)]
SafeOtp = Annotated[str, safe(Kind.OTP, 6, 6)]
SafeShortText20 = Annotated[str, safe(Kind.SHORT_TEXT, 20)]
SafeShortText40 = Annotated[str, safe(Kind.SHORT_TEXT, 40)]
SafeShortText50 = Annotated[str, safe(Kind.SHORT_TEXT, 50)]
SafeShortText60 = Annotated[str, safe(Kind.SHORT_TEXT, 60)]
SafeShortText120 = Annotated[str, safe(Kind.SHORT_TEXT, 120)]
SafeText300 = Annotated[str, safe(Kind.TEXT, 300)]
SafeText500 = Annotated[str, safe(Kind.TEXT, 500)]
SafeText1000 = Annotated[str, safe(Kind.TEXT, 1000)]
SafeText2000 = Annotated[str, safe(Kind.TEXT, 2000)]
SafeChatMessage = Annotated[str, safe(Kind.CHAT, 2000)]
SafeSearchQuery = Annotated[str, safe(Kind.SEARCH, 64)]
SafeOpaqueToken64 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 64)]
SafeOpaqueToken128 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 128)]
SafeOpaqueToken256 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 256)]
SafeOpaqueToken512 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 512)]
SafeOpaqueToken2048 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 2048)]
SafeOpaqueToken4096 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 4096)]
SafeOpaqueToken16384 = Annotated[str, safe(Kind.OPAQUE_TOKEN, 16384)]
SafeOpaqueToken65536 = Annotated[
    str, safe(Kind.OPAQUE_TOKEN, 65536)
]  # S11: App Store notifications
SafeReferralCode = Annotated[str, safe(Kind.REFERRAL_CODE, 12, 6)]
SafeBarcode = Annotated[str, safe(Kind.BARCODE, 14, 8)]
SafeTimezone = Annotated[str, safe(Kind.TIMEZONE, 64)]
SafeLocale = Annotated[str, safe(Kind.LOCALE, 5, 2)]
SafeFileName = Annotated[str, safe(Kind.FILE_NAME, 100)]
SafeAppVersion = Annotated[str, safe(Kind.APP_VERSION, 20, 5)]
SafeDeviceToken = Annotated[str, safe(Kind.DEVICE_TOKEN, 4096)]
SafeCode40 = Annotated[str, safe(Kind.CODE, 40)]
SafeYearMonth = Annotated[str, safe(Kind.YEAR_MONTH, 7, 7)]

ALL_SAFE_TYPES: dict[str, SafeString] = {
    name: alias.__metadata__[0]
    for name, alias in list(globals().items())
    if name.startswith("Safe") and hasattr(alias, "__metadata__")
}
