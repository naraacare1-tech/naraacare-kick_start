"""Transactional email: no user text, escaped values, dev outbox, never logged."""

from __future__ import annotations

from email import message_from_bytes
from email.message import Message
from pathlib import Path

import pytest

from app.integrations.email import SUBJECTS, OutboxSender, render, send_quietly


def test_every_template_renders() -> None:
    for template in SUBJECTS:
        subject, text, markup = render(template, {"code": "123456", "minutes": "15"})
        assert subject and text and markup
        assert "$" not in text and "$" not in markup


@pytest.mark.parametrize("value", ["<b>x</b>", "1234 <script>", "a b", "", "x" * 13])
def test_values_outside_the_allow_list_are_refused(value: str) -> None:
    with pytest.raises(ValueError, match="alphanumeric"):
        render("otp_verification", {"code": value})


def test_unknown_template_is_refused() -> None:
    with pytest.raises(ValueError, match="unknown"):
        render("phishing", {})


async def test_outbox_writes_an_eml_file_and_logs_no_code(
    tmp_path: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    sender = OutboxSender(sender="no-reply@mail.naraacare.local", directory=tmp_path / "outbox")
    await sender.send("priya@example.com", "otp_verification", {"code": "482913"})
    files = list((tmp_path / "outbox").glob("otp_verification-*.eml"))
    assert len(files) == 1
    message: Message = message_from_bytes(files[0].read_bytes())
    assert message["To"] == "priya@example.com"
    assert message["Subject"] == SUBJECTS["otp_verification"]
    parts = [p.get_payload(decode=True) for p in message.walk() if not p.is_multipart()]
    assert all(b"482913" in p for p in parts if isinstance(p, bytes))
    out = capsys.readouterr().out
    assert "482913" not in out and "priya@example.com" not in out


async def test_send_quietly_swallows_and_logs_failures(capsys: pytest.CaptureFixture[str]) -> None:
    class Broken:
        async def send(self, *_: object) -> None:
            raise ConnectionRefusedError("smtp down")

    await send_quietly(Broken(), "priya@example.com", "otp_verification", {"code": "111111"})
    out = capsys.readouterr().out
    assert "email_send_failed" in out and "111111" not in out
