"""Safe* validators (doc 04 §1.2, doc 07 §4.2): every payload rejected, real input accepted."""

from __future__ import annotations

from typing import Any

import pytest
from pydantic import BaseModel, ConfigDict, TypeAdapter, ValidationError

from app.core.security import validators as v
from app.core.security.validators import ALL_SAFE_TYPES, UNSAFE_INPUT, contains_unsafe_content
from tests.security.payloads import load_payloads

PAYLOADS = load_payloads()
ADAPTERS: dict[str, TypeAdapter[str]] = {
    name: TypeAdapter(getattr(v, name)) for name in ALL_SAFE_TYPES
}


def _accepts(type_name: str, value: Any) -> bool:
    try:
        ADAPTERS[type_name].validate_python(value)
    except ValidationError:
        return False
    return True


@pytest.mark.parametrize("type_name", sorted(ALL_SAFE_TYPES))
def test_every_payload_rejected_by_every_type(type_name: str) -> None:
    accepted = [p for p in PAYLOADS if _accepts(type_name, p)]
    assert accepted == [], f"{type_name} accepted {len(accepted)} payloads"


def test_reject_patterns_catch_every_payload_on_their_own() -> None:
    """The R1-R9 layer alone (no allow-list) already rejects the whole list for free text."""
    missed = [p for p in PAYLOADS if not contains_unsafe_content(p, multiline=True)]
    assert missed == []


def test_rejection_error_is_generic_and_never_echoes_input() -> None:
    with pytest.raises(ValidationError) as info:
        ADAPTERS["SafeText500"].validate_python("<script>alert('x')</script>")
    error = info.value.errors(include_input=False)[0]
    assert error["type"] == UNSAFE_INPUT
    assert error["msg"] == "Input contains characters that are not allowed"
    assert "script" not in str(error)


# ---------------------------------------------------------------------------------- legit input
NAMES = [
    "Priya Sharma", "O'Brien", "Jean-Luc Picard", "Anne-Marie", "D’Souza", "Dr. Rao",
    "Ravi", "Zoë Kravitz", "José Álvarez", "Mary Jane Watson",
    "प्रिया शर्मा", "अनन्या", "राहुल वर्मा",          # Hindi (Devanagari)
    "स्नेहा पाटील", "ज्ञानेश्वर",                     # Marathi
    "பிரியா", "கார்த்திக் ராஜா",                    # Tamil
    "ప్రియ", "శ్రీనివాస్",                          # Telugu
    "ಪ್ರಿಯಾ", "ಮಂಜುನಾಥ",                           # Kannada
    "പ്രിയ", "ശ്രീലക്ഷ്മി",                          # Malayalam
    "প্রিয়া", "সৌরভ গাঙ্গুলী",                      # Bengali
    "પ્રિયા", "હાર્દિક",                             # Gujarati
    "ਪ੍ਰਿਯਾ", "ਗੁਰਪ੍ਰੀਤ",                            # Punjabi
    "ପ୍ରିୟା",                                       # Odia
    "محمد علی",                                    # Urdu
]  # fmt: skip
SHORT_TEXTS = [
    "Moong Dal Chilla", "Aloo Paratha (2 pieces)", "Salt & pepper", "100% juice",
    "Dal, rice, roti", "Tea/coffee", "Curd + rice", "Poha - 1 plate", "Rajma chawal",
    "Paneer tikka", "Masala dosa", "Idli (3)", "Upma", "Sabudana khichdi", "Chole bhature",
    "घर का खाना", "दाल चावल", "Mom's kitchen", "Family 2026", "Morning walk",
]  # fmt: skip
TEXTS = [
    "Had a light dinner today.\nFeeling good!",
    "Is 2 katori dal ok? Yes: protein is fine; carbs too.",
    'Doctor said "drink more water" #health',
    "Meeting @ 5 - reminder",
    "Line one\r\nLine two",
    "मुझे आज बहुत प्यास लगी!",
    "Can I eat mangoes daily?",
    "Wake up at 6:30; sleep by 10:30.",
    "Rating: 5/5 (great)",
    "Notes: 3 meals, 2 snacks.",
]
CHATS = [
    "Great job 👏",
    "See you at 7 🙂",
    "Family 👨\u200d👩\u200d👧 dinner tonight",  # ZWJ sequence
    "Love it ❤️",  # VS16
    "Thumbs up 👍🏽",  # skin tone modifier
    "Go India 🇮🇳!",
    "Well done!!",
]
SEARCHES = [
    "dal",
    "moong dal",
    "paneer_65",
    "priya.s",
    "d'souza",
    "a&w",
    "chai",
    "रोटी",
    "idli",
    "x",
]
USERNAMES = ["priya.s", "rahul_99", "anna", "a1b", "the.real.dev", "user_name.x", "x9z", "abc"]
EMAILS = [
    "priya@example.com",
    "Rahul.Verma+fit@Example.co.in",
    "a@b.io",
    "first.last@sub.domain.org",
]
PASSWORDS = ["Correct1Horse", "Passw0rd!Long", "हिंदी Pass 9", "  Spaces9 Inside  ", "Ünïcödé1x"]
OTPS = ["000000", "123456", "999999"]
TOKENS = ["abc.DEF_ghi-jkl~mno+pqr/stu=", "eyJhbGciOiJFUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln", "A" * 256]
REFERRALS = ["PRIYA26", "ab12cd", "XYZ123456789"]
BARCODES = ["8901058000290", "96385074", "036000291452", "10012345678902"]
TIMEZONES = ["Asia/Kolkata", "UTC", "America/New_York", "Europe/London", "Asia/Dubai"]
LOCALES = ["en", "en-IN", "hi", "hi-IN"]
FILE_NAMES = ["photo.png", "IMG_2026-10-28.jpg", "scan 1.jpeg", "report_final.png"]
APP_VERSIONS = ["1.0.0", "2.13.4+57", "10.0.12"]
DEVICE_TOKENS = [
    "fcm:APA91bHPRgkF3JUikC4ENAHEeMrd41Zxv3hVZjC9KtT8OvPVGJ-hQMRKRrZuJAEcl7B338qju59zJMjw2DeLc"
]
CODES = ["diabetes", "allergy_peanut", "none", "kidney_disease", "nutr.floor.male_kcal"]

LEGIT: list[tuple[str, str]] = (
    [("SafeName", x) for x in NAMES]
    + [("SafeShortText120", x) for x in SHORT_TEXTS]
    + [("SafeText500", x) for x in TEXTS]
    + [("SafeChatMessage", x) for x in [*CHATS, *TEXTS]]
    + [("SafeSearchQuery", x) for x in SEARCHES]
    + [("SafeUsername", x) for x in USERNAMES]
    + [("SafeEmail", x) for x in EMAILS]
    + [("SafePassword", x) for x in PASSWORDS]
    + [("SafeNewPassword", x) for x in PASSWORDS]
    + [("SafeOtp", x) for x in OTPS]
    + [("SafeOpaqueToken256", x) for x in TOKENS]
    + [("SafeReferralCode", x) for x in REFERRALS]
    + [("SafeBarcode", x) for x in BARCODES]
    + [("SafeTimezone", x) for x in TIMEZONES]
    + [("SafeLocale", x) for x in LOCALES]
    + [("SafeFileName", x) for x in FILE_NAMES]
    + [("SafeAppVersion", x) for x in APP_VERSIONS]
    + [("SafeDeviceToken", x) for x in DEVICE_TOKENS]
    + [("SafeCode40", x) for x in CODES]
)


def test_at_least_100_legitimate_samples() -> None:
    assert len(LEGIT) >= 100


@pytest.mark.parametrize(("type_name", "value"), LEGIT)
def test_legitimate_input_accepted(type_name: str, value: str) -> None:
    assert _accepts(type_name, value), f"{type_name} rejected a legitimate value"


# ------------------------------------------------------------------------- per-type behaviour
@pytest.mark.parametrize(
    ("type_name", "raw", "expected"),
    [
        ("SafeUsername", "Priya.S", "priya.s"),
        ("SafeEmail", "Priya@Example.COM", "priya@example.com"),
        ("SafeReferralCode", "priya26", "PRIYA26"),
        ("SafeName", "  Priya  ", "Priya"),
        ("SafeShortText40", "Ａbc", "Abc"),  # full-width A folded by NFKC
        ("SafeOtp", "１２３４５６", "123456"),  # full-width digits
        ("SafePassword", "  Spaces9 Inside  ", "  Spaces9 Inside  "),  # passwords keep spaces
    ],
)
def test_normalisation(type_name: str, raw: str, expected: str) -> None:
    assert ADAPTERS[type_name].validate_python(raw) == expected


@pytest.mark.parametrize(
    ("type_name", "value"),
    [
        ("SafeName", "Priya2"),  # digits are not part of a name
        ("SafeName", "..."),  # needs a letter
        ("SafeName", "Priya\nSharma"),  # single line
        ("SafeName", "Priya\tSharma"),
        ("SafeName", "a" * 101),
        ("SafeUsername", "ab"),
        ("SafeUsername", "priya..s"),
        ("SafeUsername", "priya_.s"),
        ("SafeUsername", ".priya"),
        ("SafeUsername", "priya s"),
        ("SafeEmail", "not-an-email"),
        ("SafeEmail", "рriya@example.com"),  # Cyrillic look-alike local part
        ("SafePassword", "short1A"),
        ("SafePassword", "a" * 129),
        ("SafeNewPassword", "alllowercase1"),  # needs an upper-case letter
        ("SafeNewPassword", "NoDigitsHere"),
        ("SafeOtp", "12345"),
        ("SafeOtp", "12345a"),
        ("SafeShortText20", "a" * 21),
        ("SafeShortText120", "price = 5"),  # '=' not allowed
        ("SafeText500", "use {braces}"),
        ("SafeText500", "back\\slash"),
        ("SafeText500", "tick `code`"),
        ("SafeText500", "cost $5"),
        ("SafeChatMessage", "bad \u200d join"),  # ZWJ outside an emoji sequence
        ("SafeSearchQuery", ""),
        ("SafeSearchQuery", "a" * 65),
        ("SafeOpaqueToken128", "has space"),
        ("SafeOpaqueToken128", "a" * 129),
        ("SafeReferralCode", "AB12"),
        ("SafeBarcode", "8901058000291"),  # wrong check digit
        ("SafeBarcode", "123456789"),  # not a GTIN length
        ("SafeTimezone", "Mars/Olympus"),
        ("SafeTimezone", "asia/kolkata"),
        ("SafeLocale", "fr"),  # well-formed but unsupported
        ("SafeLocale", "EN"),
        ("SafeFileName", "photo.gif"),
        ("SafeFileName", "../photo.png"),
        ("SafeFileName", "a..b.png"),
        ("SafeAppVersion", "1.0"),
        ("SafeAppVersion", "1.0.0-beta"),
        ("SafeDeviceToken", "token with space"),
    ],
)
def test_invalid_values_rejected(type_name: str, value: str) -> None:
    assert not _accepts(type_name, value)


@pytest.mark.parametrize(
    "value",
    [
        "java script:alert(1)",
        "java\tscript:alert(1)",
        "JaVaScRiPt:alert(1)",
        "x onclick =alert(1)",
        "{{7*7}}",
        "${7*7}",
        "#{7*7}",
        "%3Cb%3E",
        "%253Cb%253E",
        "&lt;b&gt;",
        "&#60;b&#62;",
        "&#x3c;b",
        "&#0000060b",
        "\\u003cb",
        "\\x3cb",
        "＜b＞",
        "expression(alert(1))",
        "background:url(x)",
        "@import 'x'",
        "data:text/html;base64,AAAA",
        "abc\x00def",
        "abc\u202eevil",
        "zero\u200bwidth",
        "bom\ufeff",
    ],
)
def test_obfuscated_markup_rejected_even_by_lenient_types(value: str) -> None:
    for type_name in ("SafeText2000", "SafeChatMessage", "SafePassword"):
        assert not _accepts(type_name, value), type_name


def test_non_string_input_rejected() -> None:
    assert not _accepts("SafeName", 123)
    assert not _accepts("SafeOtp", 123456)


def test_schema_publishes_max_length() -> None:
    class Example(BaseModel):
        model_config = ConfigDict(extra="forbid", strict=True)
        name: v.SafeName
        note: v.SafeText500

    schema = Example.model_json_schema()["properties"]
    assert schema["name"]["maxLength"] == 100
    assert schema["note"]["maxLength"] == 500


def test_all_documented_types_exist() -> None:
    expected = {
        "SafeName", "SafeUsername", "SafeEmail", "SafePassword", "SafeOtp", "SafeShortText120",
        "SafeText2000", "SafeChatMessage", "SafeSearchQuery", "SafeOpaqueToken256",
        "SafeReferralCode", "SafeBarcode", "SafeTimezone", "SafeLocale", "SafeFileName",
        "SafeAppVersion", "SafeDeviceToken",
    }  # fmt: skip
    assert expected <= set(ALL_SAFE_TYPES)


def test_shared_vectors_file_is_up_to_date() -> None:
    """tests/security/payloads/validator_vectors.json (copied to the mobile repo) == LEGIT."""
    import json  # noqa: PLC0415
    from pathlib import Path  # noqa: PLC0415

    path = Path(__file__).resolve().parents[2] / "security/payloads/validator_vectors.json"
    grouped: dict[str, list[str]] = {}
    for kind, value in LEGIT:
        grouped.setdefault(kind, []).append(value)
    assert json.loads(path.read_text(encoding="utf-8"))["accept"] == grouped
