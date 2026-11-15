"""Support forwarding (Session 14, OQ-51). Run by the taskiq scheduler only; ``ops`` functions are
granted to the worker role alone.

Every few minutes, tickets and feature requests not yet emailed go to ``SUPPORT_INBOX_ADDRESS`` as
plain-text messages (``PlainEmailSender``): no HTML part, fixed headers plus the ticket reference,
and the user's account address as ``Reply-To``. A screenshot is not attached: support opens it from
the admin tools (S16), so the image never leaves our storage by email. Each item is marked
forwarded only after the send succeeds; failures are retried by the next run (20 attempts at most).
Nothing user-entered is logged.
"""

from __future__ import annotations

from collections.abc import Mapping
from functools import partial
from typing import Any

import structlog

from app.integrations.email import PlainEmailSender
from app.repositories import support_repo
from app.repositories.base import Database

log = structlog.get_logger(__name__)

BATCH = 50
CATEGORY_LABELS = {
    "app_crash": "App crash",
    "data_sync": "Data sync",
    "billing": "Billing",
    "device_link": "Device link",
    "account": "Account",
    "other": "Other",
}


def compose(row: Mapping[str, Any]) -> tuple[str, str]:
    """(subject, body). The subject holds fixed text and the server-made reference only."""
    username = f"@{row['username']}" if row["username"] else "(no username)"
    if row["kind"] == "ticket":
        category = CATEGORY_LABELS.get(str(row["category"]), "Other")
        subject = f"[NaraaCare support] {row['ticket_ref']} - {category}"
        lines = [
            f"Ticket: {row['ticket_ref']}",
            f"Category: {category}",
            f"User: {username} ({row['user_id']})",
            f"Created: {row['created_at']:%Y-%m-%d %H:%M} UTC",
            f"Screenshot: {'yes (see admin tools)' if row['screenshot_key'] else 'no'}",
            "",
            "Description:",
            str(row["body"]),
        ]
    else:
        subject = "[NaraaCare feature request]"
        lines = [
            f"User: {username} ({row['user_id']})",
            f"Created: {row['created_at']:%Y-%m-%d %H:%M} UTC",
            "",
            "What should we add?",
            str(row["title"]),
            "",
            "How would this help?",
            str(row["body"]),
        ]
    return subject, "\n".join(lines) + "\n"


async def forward_support(*, db: Database, sender: PlainEmailSender, inbox: str) -> int:
    rows = await db.run(lambda s: support_repo.unforwarded(s, BATCH))
    sent = 0
    for row in rows:
        subject, body = compose(row)
        try:
            await sender.send_plain(inbox, subject, body, reply_to=str(row["reply_email"]))
            ok = True
            sent += 1
        except Exception as exc:  # retried by the next run
            ok = False
            log.warning("support_forward_failed", kind=row["kind"], error=type(exc).__name__)
        await db.run(
            partial(
                support_repo.mark_forwarded, kind=str(row["kind"]), item_id=row["item_id"], ok=ok
            )
        )
    return sent
