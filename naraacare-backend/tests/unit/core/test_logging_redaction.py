"""Logs never contain PII, secrets or exception messages (doc 07 SEC-7.4)."""

from __future__ import annotations

import json

import pytest
import structlog

from app.core.logging import configure_logging, redact, safe_exception


@pytest.fixture
def lines(capsys: pytest.CaptureFixture[str]) -> list[dict[str, object]]:
    configure_logging("INFO")
    log = structlog.get_logger("test")
    log.info(
        "user_event",
        email="priya@example.com",
        password="Correct1Horse",
        refresh_token="abc",
        full_name="Priya",
        weight_kg=62.5,
        height_cm=165,
        kcal=1700,
        volume_ml=250,
        body="{...}",
        description="note",
        otp_code="123456",
        authorization="Bearer x",
        status=200,
        error_code="VALIDATION_FAILED",
        nested={"user": {"email": "x@y.z", "ok": 1}},
        items=[{"name": "dal", "qty": 2}],
        long="a" * 2000,
    )
    out = capsys.readouterr().out.strip().splitlines()
    return [json.loads(line) for line in out]


def test_pii_keys_are_dropped(lines: list[dict[str, object]]) -> None:
    record = lines[-1]
    for key in (
        "email", "password", "refresh_token", "full_name", "weight_kg", "height_cm", "kcal",
        "volume_ml", "body", "description", "otp_code", "authorization",
    ):  # fmt: skip
        assert key not in record, key
    assert record["status"] == 200
    assert record["error_code"] == "VALIDATION_FAILED"
    assert record["nested"] == {"user": {"ok": 1}}
    assert record["items"] == [{"qty": 2}]


def test_long_values_truncated(lines: list[dict[str, object]]) -> None:
    value = lines[-1]["long"]
    assert isinstance(value, str)
    assert len(value) < 600
    assert value.endswith("[truncated]")


def test_exception_message_is_dropped_but_type_and_frames_kept() -> None:
    try:
        raise ValueError("user typed priya@example.com")
    except ValueError as exc:
        event = safe_exception(None, "error", {"event": "boom", "exc_info": exc})
    rendered = json.dumps(event)
    assert "priya@example.com" not in rendered
    assert event["exception"]["type"] == "builtins.ValueError"
    assert event["exception"]["frames"]


def test_redact_keeps_event_name() -> None:
    assert redact(None, "info", {"event": "name_changed", "name": "x"}) == {"event": "name_changed"}


def test_url_logging_libraries_are_quiet() -> None:
    import logging  # noqa: PLC0415

    configure_logging("DEBUG")
    for name in ("httpx", "httpx2", "httpcore", "urllib3", "uvicorn.access"):
        assert logging.getLogger(name).getEffectiveLevel() >= logging.WARNING, name
    configure_logging("INFO")
