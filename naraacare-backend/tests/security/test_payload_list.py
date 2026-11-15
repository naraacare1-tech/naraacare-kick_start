"""The payload list itself is sane. The Safe* field sweep arrives in Session 04."""

from __future__ import annotations

import importlib.util
from pathlib import Path

from tests.security.payloads import (
    EXPECTED_VERSION,
    PAYLOAD_FILE,
    load_payloads,
    payload_list_version,
)

ROOT = Path(__file__).resolve().parents[2]


def test_version_is_expected() -> None:
    assert payload_list_version() == EXPECTED_VERSION


def test_list_is_large_and_unique() -> None:
    payloads = load_payloads()
    assert len(payloads) >= 300
    assert len(payloads) == len(set(payloads))


def test_generated_file_is_up_to_date() -> None:
    spec = importlib.util.spec_from_file_location(
        "build_payloads", ROOT / "tools/build_payloads.py"
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert PAYLOAD_FILE.read_text(encoding="utf-8") == module.build()


def test_control_characters_survive_round_trip() -> None:
    payloads = load_payloads()
    assert "abc\x00def" in payloads
    assert chr(0x202E) + "evil" in payloads  # right-to-left override
