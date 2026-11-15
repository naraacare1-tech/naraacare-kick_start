"""Transactional email: sign-up and reset codes, lockout and password-change notices (doc 07 §4.6).

* Templates are fixed files in ``app/templates/email``; they never contain user-entered text. The
  only values are codes and numbers, checked against an allow-list before rendering and
  HTML-escaped in the HTML part (so a template change can never turn a value into markup).
* ``OutboxSender`` (dev): each message is written as an ``.eml`` file to ``EMAIL_OUTBOX_DIR`` for
  the developer to open. Codes are never logged.
* ``SmtpSender`` (staging/prod, any provider): STARTTLS with certificate verification is mandatory.
* Logs name the template and the outcome only, never the recipient or the values.
* Support forwarding (S14) is the one message that carries user-entered text: it is sent as
  ``text/plain`` only (no HTML part, so nothing can render as markup), the text was already
  validated as plain text by the API and the database, and headers hold fixed text plus the ticket
  reference only (the user's verified account address goes in ``Reply-To``).
"""

from __future__ import annotations

import html
import smtplib
import ssl
import uuid
from collections.abc import Mapping
from email.message import EmailMessage
from email.utils import make_msgid
from pathlib import Path
from string import Template
from typing import Protocol

import anyio.to_thread
import regex
import structlog

log = structlog.get_logger(__name__)

TEMPLATE_DIR = Path(__file__).resolve().parents[1] / "templates" / "email"
SUBJECTS: dict[str, str] = {
    "otp_verification": "Your NaraaCare verification code",
    "password_reset": "Your NaraaCare password reset code",  # nosec B105 - email subject
    "lockout_notice": "Sign-in to NaraaCare is paused",
    "password_changed": "Your NaraaCare password was changed",  # nosec B105 - email subject
    "deletion_scheduled": "Your NaraaCare account will be deleted in 30 days",
    "deletion_completed": "Your NaraaCare account has been deleted",
}
_SAFE_VALUE = regex.compile(r"^[0-9A-Za-z]{1,12}$")
SMTP_TIMEOUT_S = 10


class EmailSender(Protocol):
    async def send(self, to: str, template: str, values: Mapping[str, str]) -> None: ...


class PlainEmailSender(Protocol):
    async def send_plain(
        self, to: str, subject: str, body: str, *, reply_to: str | None = None
    ) -> None: ...


_HEADER_SAFE = regex.compile(r"^[ -~]{1,200}$")


def build_plain_message(
    sender: str, to: str, subject: str, body: str, *, reply_to: str | None = None
) -> EmailMessage:
    if not _HEADER_SAFE.match(subject) or (
        reply_to is not None and not _HEADER_SAFE.match(reply_to)
    ):
        raise ValueError("header values must be printable ASCII")
    message = EmailMessage()
    message["From"] = sender
    message["To"] = to
    message["Subject"] = subject
    if reply_to:
        message["Reply-To"] = reply_to
    message["Message-ID"] = make_msgid(domain=sender.rsplit("@", 1)[-1])
    message.set_content(body, subtype="plain", charset="utf-8")
    return message


def render(template: str, values: Mapping[str, str]) -> tuple[str, str, str]:
    """(subject, text, html). Unknown templates or non-allow-listed values raise ValueError."""
    if template not in SUBJECTS:
        raise ValueError("unknown email template")
    if not all(_SAFE_VALUE.match(v) for v in values.values()):
        raise ValueError("email template values must be short alphanumeric codes")
    text = Template((TEMPLATE_DIR / f"{template}.txt").read_text(encoding="utf-8"))
    markup = Template((TEMPLATE_DIR / f"{template}.html").read_text(encoding="utf-8"))
    escaped = {k: html.escape(v) for k, v in values.items()}
    return SUBJECTS[template], text.substitute(values), markup.substitute(escaped)


def build_message(sender: str, to: str, template: str, values: Mapping[str, str]) -> EmailMessage:
    subject, text, markup = render(template, values)
    message = EmailMessage()
    message["From"] = sender
    message["To"] = to
    message["Subject"] = subject
    message["Message-ID"] = make_msgid(domain=sender.rsplit("@", 1)[-1])
    message.set_content(text)
    message.add_alternative(markup, subtype="html")
    return message


class OutboxSender:
    def __init__(self, *, sender: str, directory: Path) -> None:
        self._sender = sender
        self._directory = directory

    async def send(self, to: str, template: str, values: Mapping[str, str]) -> None:
        message = build_message(self._sender, to, template, values)
        self._directory.mkdir(parents=True, exist_ok=True)
        path = self._directory / f"{template}-{uuid.uuid4().hex}.eml"
        await anyio.to_thread.run_sync(path.write_bytes, bytes(message))
        log.info("email_written_to_outbox", template=template)

    async def send_plain(
        self, to: str, subject: str, body: str, *, reply_to: str | None = None
    ) -> None:
        message = build_plain_message(self._sender, to, subject, body, reply_to=reply_to)
        self._directory.mkdir(parents=True, exist_ok=True)
        path = self._directory / f"support-{uuid.uuid4().hex}.eml"
        await anyio.to_thread.run_sync(path.write_bytes, bytes(message))
        log.info("email_written_to_outbox", template="support_forward")


class SmtpSender:
    def __init__(
        self,
        *,
        sender: str,
        host: str,
        port: int,
        username: str | None,
        password: str | None,
    ) -> None:
        self._sender = sender
        self._host = host
        self._port = port
        self._username = username
        self._password = password

    def _send_sync(self, message: EmailMessage) -> None:
        context = ssl.create_default_context()
        with smtplib.SMTP(self._host, self._port, timeout=SMTP_TIMEOUT_S) as smtp:
            smtp.starttls(context=context)
            if self._username and self._password:
                smtp.login(self._username, self._password)
            smtp.send_message(message)

    async def send(self, to: str, template: str, values: Mapping[str, str]) -> None:
        message = build_message(self._sender, to, template, values)
        await anyio.to_thread.run_sync(self._send_sync, message)
        log.info("email_sent", template=template)

    async def send_plain(
        self, to: str, subject: str, body: str, *, reply_to: str | None = None
    ) -> None:
        message = build_plain_message(self._sender, to, subject, body, reply_to=reply_to)
        await anyio.to_thread.run_sync(self._send_sync, message)
        log.info("email_sent", template="support_forward")


async def send_quietly(
    sender: EmailSender, to: str, template: str, values: Mapping[str, str]
) -> None:
    """For background tasks: a failed send is logged (type only) and never reaches the client."""
    try:
        await sender.send(to, template, values)
    except Exception as exc:  # the response has already been sent
        log.warning("email_send_failed", template=template, exc_type=type(exc).__name__)
