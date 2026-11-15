"""Password policy (OQ-29)."""

from __future__ import annotations

import hashlib

import pytest

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.hashing import Hasher
from app.core.security.passwords import (
    COMMON_PASSWORDS_FILE,
    check_confirmation,
    check_policy,
    common_passwords,
    is_reused,
)


def test_common_password_list_is_the_pinned_one() -> None:
    digest = hashlib.sha256(COMMON_PASSWORDS_FILE.read_bytes()).hexdigest()
    assert digest == "9dcf662182e40882c3fa3b8502b83a40bb6476901e320132c22776c47e3b2383"
    assert len(common_passwords()) == 10001
    assert "password1" in common_passwords()


@pytest.mark.parametrize(
    "password",
    [
        "alllowercase1",  # no upper case
        "NoDigitsHere",  # no digit
        "Password1",  # common (case-insensitive)
        "Qwerty123",  # common
        "Priya2026x",  # email local part (case-insensitive)
    ],
)
def test_weak_passwords_are_refused(password: str) -> None:
    with pytest.raises(AppError) as info:
        check_policy(password, email="PRIYA2026X@example.com")
    assert info.value.code is ErrorCode.PASSWORD_WEAK
    assert password not in str(info.value)


@pytest.mark.parametrize("password", ["Correct1Horse", "Moong-Dal 2 Katori", "हिंदी Pass 9"])
def test_reasonable_passwords_pass(password: str) -> None:
    check_policy(password, email="priya@example.com")


def test_confirmation_mismatch_names_the_field_only() -> None:
    with pytest.raises(AppError) as info:
        check_confirmation("Correct1Horse", "Correct1Hors")
    assert info.value.code is ErrorCode.VALIDATION_FAILED
    assert info.value.fields == ["confirm_password"]


async def test_reuse_detection_against_argon2_history() -> None:
    hasher = Hasher(memory_kib=8192, time_cost=1, parallelism=1)
    history = [hasher.hash("Old1Password"), hasher.hash("Older2Password")]
    assert await is_reused(hasher, history, "Older2Password")
    assert not await is_reused(hasher, history, "Brand3NewOne")
