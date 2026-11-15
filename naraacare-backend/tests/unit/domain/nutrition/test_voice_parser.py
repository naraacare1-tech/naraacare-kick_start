"""Voice transcript parsing (OQ-43): quantities, units and sizes in English and Hinglish."""

from __future__ import annotations

from decimal import Decimal

import pytest

from app.domain.nutrition.voice_parser import (
    MAX_PARTS,
    ParsedPart,
    parse_transcript,
    snap_quantity,
)


def part(quantity: str, unit: str | None, size: str | None, phrase: str) -> ParsedPart:
    return ParsedPart(Decimal(quantity), unit, size, phrase)


@pytest.mark.parametrize(
    ("transcript", "expected"),
    [
        (
            "do roti aur ek katori dal",
            [part("2", None, None, "roti"), part("1", "katori", None, "dal")],
        ),
        (
            "1.5 katori rice, half plate biryani",
            [part("1.5", "katori", None, "rice"), part("1", "plate", "half", "biryani")],
        ),
        (
            "aadha glass milk and 2 chapati",
            [part("0.5", "glass", None, "milk"), part("2", None, None, "chapati")],
        ),
        ("Maine teen badi roti khayi", [part("3", None, "large", "roti")]),
        ("two cups of chai", [part("2", "cup", None, "chai")]),
        ("dedh bowl dahi", [part("1.5", "bowl", None, "dahi")]),
        ("1/2 plate pulao", [part("0.5", "plate", None, "pulao")]),
        ("ek chhoti katori sabzi", [part("1", "katori", "small", "sabzi")]),
        ("apple", [part("1", None, None, "apple")]),
    ],
)
def test_parses_quantities_units_and_sizes(transcript: str, expected: list[ParsedPart]) -> None:
    assert parse_transcript(transcript) == expected


def test_full_only_describes_plates() -> None:
    assert parse_transcript("full katori dal") == [part("1", "katori", None, "dal")]
    assert parse_transcript("ek full plate rice") == [part("1", "plate", "full", "rice")]


def test_empty_and_filler_only_transcripts_give_nothing() -> None:
    assert parse_transcript("") == []
    assert parse_transcript("maine khaya aur and ,") == []


def test_at_most_twenty_parts() -> None:
    transcript = ", ".join(f"food{i}" for i in range(30))
    assert len(parse_transcript(transcript)) == MAX_PARTS


def test_phrases_are_capped_at_sixty_characters() -> None:
    (only,) = parse_transcript("x" * 100)
    assert len(only.phrase) == 60


@pytest.mark.parametrize(
    ("value", "snapped"),
    [("0.1", "0.25"), ("0.3", "0.25"), ("0.4", "0.5"), ("1.125", "1.25"), ("25", "20"), ("3", "3")],
)
def test_quantities_snap_to_meal_rules(value: str, snapped: str) -> None:
    assert snap_quantity(Decimal(value)) == Decimal(snapped)
