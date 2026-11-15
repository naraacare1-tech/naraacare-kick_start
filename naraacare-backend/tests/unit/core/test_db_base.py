"""Repository rules: only stored function/procedure calls; SQLSTATE mapping (doc 07 SEC-4.1)."""

from __future__ import annotations

import pytest

from app.core.error_catalogue import DB_DETAIL_CODES, ErrorCode
from app.repositories.base import DbError, RetryableDbError, db_call, map_db_error


@pytest.mark.parametrize(
    "statement",
    [
        "SELECT * FROM app.fn_get_profile(:user_id)",
        "SELECT * FROM ref.fn_bootstrap()",
        "SELECT ops.fn_ping() AS ok",
        "CALL auth.pr_verify_otp(:challenge_id, :code_ok, NULL, NULL, NULL, NULL)",
    ],
)
def test_function_and_procedure_calls_are_allowed(statement: str) -> None:
    assert db_call(statement).text == statement


@pytest.mark.parametrize(
    "statement",
    [
        "SELECT * FROM auth.user_account",  # table access
        "SELECT * FROM app.fn_get_profile('x')",  # literal instead of a bound parameter
        "SELECT * FROM app.fn_get_profile(:id); DROP TABLE x",
        "SELECT * FROM app.fn_get_profile(:id) -- comment",
        "CALL auth.fn_lookup(:x)",  # procedures must be pr_
        "SELECT * FROM app.pr_set_username(:x)",  # functions must be fn_
        "DELETE FROM auth.refresh_token",
        "select * from app.fn_get_profile(:user_id)",
        "SELECT * FROM fn_get_profile(:user_id)",  # schema-qualified only
    ],
)
def test_anything_else_is_refused_at_import_time(statement: str) -> None:
    with pytest.raises(ValueError, match="not a stored function/procedure call"):
        db_call(statement)


@pytest.mark.parametrize(
    ("sqlstate", "detail", "expected"),
    [
        ("22023", None, ErrorCode.VALIDATION_FAILED),
        ("23514", None, ErrorCode.VALIDATION_FAILED),
        ("23503", None, ErrorCode.VALIDATION_FAILED),
        ("22P02", None, ErrorCode.VALIDATION_FAILED),
        ("42501", "NOT_FOUND", ErrorCode.NOT_FOUND),
        ("23505", None, ErrorCode.ALREADY_EXISTS),
        ("P0001", "USERNAME_TAKEN", ErrorCode.USERNAME_TAKEN),
        ("P0001", "CONSENT_REQUIRED", ErrorCode.CONSENT_REQUIRED),
        ("57014", None, ErrorCode.SERVICE_UNAVAILABLE),
    ],
)
def test_sqlstate_mapping(sqlstate: str, detail: str | None, expected: ErrorCode) -> None:
    mapped = map_db_error(DbError(sqlstate=sqlstate, detail=detail))
    assert mapped is not None
    assert mapped.code is expected


def test_serialization_failures_are_retryable() -> None:
    assert isinstance(map_db_error(DbError("40001", None)), RetryableDbError)
    assert isinstance(map_db_error(DbError("40P01", None)), RetryableDbError)


@pytest.mark.parametrize(
    ("sqlstate", "detail"), [("P0001", "SOMETHING_NEW"), ("XX000", None), (None, None)]
)
def test_unknown_errors_are_not_mapped(sqlstate: str | None, detail: str | None) -> None:
    assert map_db_error(DbError(sqlstate, detail)) is None


def test_every_database_business_code_is_catalogued() -> None:
    """Codes raised by naraacare-database procedures (functions/README.md, Session 03)."""
    raised_by_db = {
        "USERNAME_TAKEN", "USERNAME_CHANGE_TOO_SOON", "USERNAME_REQUIRED", "ONBOARDING_INCOMPLETE",
        "ONBOARDING_ALREADY_COMPLETED", "CONSENT_REQUIRED", "IDENTITY_ALREADY_LINKED",
        "ACCOUNT_NOT_ACTIVE",
    }  # fmt: skip
    assert raised_by_db <= set(DB_DETAIL_CODES)
