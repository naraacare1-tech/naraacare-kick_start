"""Password policy for sign-up, reset and change (OQ-29, doc 07 SEC-1.1).

Rules (on top of ``SafePassword``: 8-128 characters, no markup or control characters):
* at least one upper-case letter and one digit (FIG rules);
* not one of the 10,000 most common passwords (compared case-insensitively);
* not the email address or its local part;
* differs from the last 5 passwords (checked against the Argon2id history by ``is_reused``).

Violations raise 422 ``PASSWORD_WEAK`` / ``PASSWORD_REUSED`` without saying which rule failed for
the common-password case, and never echo the password.
"""

from __future__ import annotations

from collections.abc import Iterable
from functools import cache
from pathlib import Path

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.hashing import Hasher

COMMON_PASSWORDS_FILE = Path(__file__).with_name("data") / "common_passwords.txt"


@cache
def common_passwords() -> frozenset[str]:
    lines = COMMON_PASSWORDS_FILE.read_text(encoding="ascii").splitlines()
    return frozenset(line for line in lines if line and not line.startswith("#"))


def check_policy(password: str, *, email: str | None = None) -> None:
    folded = password.casefold()
    weak = (
        not any(ch.isupper() for ch in password)
        or not any(ch.isdigit() for ch in password)
        or folded in common_passwords()
        or (email is not None and folded in {email.casefold(), email.split("@")[0].casefold()})
    )
    if weak:
        raise AppError(ErrorCode.PASSWORD_WEAK, fields=["password"])


def check_confirmation(password: str, confirmation: str, field: str = "confirm_password") -> None:
    if password != confirmation:
        raise AppError(ErrorCode.VALIDATION_FAILED, fields=[field])


async def is_reused(hasher: Hasher, history: Iterable[str], candidate: str) -> bool:
    """True when the candidate matches one of the stored hashes (Argon2id, so one verify each)."""
    for stored in history:
        if await hasher.verify_async(stored, candidate):
            return True
    return False
