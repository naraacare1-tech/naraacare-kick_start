"""Auth routines (naraacare-database functions/README.md). Values travel as bound parameters only.

Procedures report expected outcomes in ``o_status`` (never raised) so attempt counters persist;
the service layer turns them into HTTP errors after the transaction has committed.
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from uuid import UUID

from app.repositories.base import DbSession, db_call

FIND_ACCOUNT = db_call("SELECT * FROM auth.fn_find_account_by_email(:email)")
UNKNOWN_EMAIL_LOCK = db_call("SELECT auth.fn_unknown_email_locked_until(:email) AS locked_until")
FIND_IDENTITY = db_call("SELECT * FROM auth.fn_find_identity(:provider, :subject)")
GET_OTP_CHALLENGE = db_call("SELECT * FROM auth.fn_get_otp_challenge(:challenge_id)")
OTP_CHALLENGE_EMAIL = db_call("SELECT * FROM auth.fn_otp_challenge_email(:challenge_id)")
PASSWORD_HISTORY = db_call("SELECT auth.fn_password_history(:user_id) AS password_hash")
CREATE_ACCOUNT = db_call(
    "CALL auth.pr_create_account("
    ":email, :password_hash, :installation_id, :code, "
    "NULL, NULL, NULL, NULL)"
)
CREATE_OAUTH_ACCOUNT = db_call(
    "CALL auth.pr_create_oauth_account(:provider, :subject, :email, :installation_id, NULL, NULL)"
)
CREATE_OTP_CHALLENGE = db_call(
    "CALL auth.pr_create_otp_challenge(:email, :purpose, :code, NULL, NULL, NULL)"
)
RESEND_OTP = db_call("CALL auth.pr_resend_otp(:challenge_id, :code, NULL, NULL)")
VERIFY_OTP = db_call("CALL auth.pr_verify_otp(:challenge_id, :code_ok, NULL, NULL, NULL, NULL)")
RECORD_LOGIN_ATTEMPT = db_call(
    "CALL auth.pr_record_login_attempt(:email, CAST(:ip AS inet), :success, NULL, NULL)"
)
ISSUE_REFRESH_TOKEN = db_call(
    "CALL auth.pr_issue_refresh_token(:user_id, :token_hash, :installation_id, NULL, NULL, NULL)"
)
ROTATE_REFRESH_TOKEN = db_call(
    "CALL auth.pr_rotate_refresh_token("
    ":token_hash, :new_token_hash, :installation_id, NULL, NULL, NULL, NULL, NULL, NULL)"
)
REVOKE_TOKENS = db_call(
    "CALL auth.pr_revoke_tokens(:user_id, :scope, :reason, :family_id, :keep_family_id, NULL)"
)
SET_PASSWORD = db_call("CALL auth.pr_set_password(:user_id, :password_hash, :keep_family_id)")
REHASH_PASSWORD = db_call("CALL auth.pr_rehash_password(:user_id, :old_hash, :new_hash, NULL)")
LINK_IDENTITY = db_call("CALL auth.pr_link_identity(:user_id, :provider, :subject, :email)")
STORE_PROVIDER_TOKEN = db_call(
    "CALL auth.pr_store_provider_token(:user_id, :provider, :subject, :token, NULL)"
)


@dataclass(frozen=True, slots=True)
class Account:
    user_id: UUID
    status: str
    role: str
    password_hash: str | None
    locked_until: datetime | None


@dataclass(frozen=True, slots=True)
class OtpChallenge:
    challenge_id: UUID
    user_id: UUID
    purpose: str
    code: str
    is_usable: bool


@dataclass(frozen=True, slots=True)
class Outcome:
    """INOUT results of a procedure call (o_ prefix removed)."""

    values: Mapping[str, Any]

    @property
    def status(self) -> str | None:
        value = self.values.get("status")
        return None if value is None else str(value)

    def __getitem__(self, key: str) -> Any:
        return self.values.get(key)


async def _call(session: DbSession, statement: Any, **params: object) -> Outcome:
    row = await session.fetch_one(statement, **params) or {}
    return Outcome({k.removeprefix("o_"): v for k, v in row.items()})


async def find_account(session: DbSession, email: str) -> Account | None:
    row = await session.fetch_one(FIND_ACCOUNT, email=email)
    if row is None:
        return None
    return Account(
        user_id=row["user_id"],
        status=row["status"],
        role=row["role"],
        password_hash=row["password_hash"],
        locked_until=row["locked_until"],
    )


async def unknown_email_locked_until(session: DbSession, email: str) -> datetime | None:
    """Derived lockout for an email with no account (doc 07 T26: no enumeration via lockout)."""
    row = await session.fetch_one(UNKNOWN_EMAIL_LOCK, email=email)
    return row["locked_until"] if row is not None else None


async def find_identity(session: DbSession, provider: str, subject: str) -> Account | None:
    row = await session.fetch_one(FIND_IDENTITY, provider=provider, subject=subject)
    if row is None:
        return None
    return Account(
        user_id=row["user_id"],
        status=row["status"],
        role=row["role"],
        password_hash=None,
        locked_until=row["locked_until"],
    )


async def get_otp_challenge(session: DbSession, challenge_id: UUID) -> OtpChallenge | None:
    row = await session.fetch_one(GET_OTP_CHALLENGE, challenge_id=challenge_id)
    if row is None:
        return None
    return OtpChallenge(
        challenge_id=row["challenge_id"],
        user_id=row["user_id"],
        purpose=row["purpose"],
        code=row["code"],
        is_usable=bool(row["is_usable"]),
    )


async def otp_challenge_email(session: DbSession, challenge_id: UUID) -> Mapping[str, Any] | None:
    return await session.fetch_one(OTP_CHALLENGE_EMAIL, challenge_id=challenge_id)


async def password_history(session: DbSession, user_id: UUID) -> Sequence[str]:
    rows = await session.fetch_all(PASSWORD_HISTORY, user_id=user_id)
    return [str(r["password_hash"]) for r in rows]


async def create_account(session: DbSession, **params: object) -> Outcome:
    return await _call(session, CREATE_ACCOUNT, **params)


async def create_oauth_account(session: DbSession, **params: object) -> Outcome:
    return await _call(session, CREATE_OAUTH_ACCOUNT, **params)


async def create_otp_challenge(
    session: DbSession, *, email: str, purpose: str, code: str
) -> Outcome:
    return await _call(session, CREATE_OTP_CHALLENGE, email=email, purpose=purpose, code=code)


async def resend_otp(session: DbSession, *, challenge_id: UUID, code: str) -> Outcome:
    return await _call(session, RESEND_OTP, challenge_id=challenge_id, code=code)


async def verify_otp(session: DbSession, *, challenge_id: UUID, code_ok: bool) -> Outcome:
    return await _call(session, VERIFY_OTP, challenge_id=challenge_id, code_ok=code_ok)


async def record_login_attempt(
    session: DbSession, *, email: str, ip: str | None, success: bool
) -> Outcome:
    return await _call(session, RECORD_LOGIN_ATTEMPT, email=email, ip=ip, success=success)


async def issue_refresh_token(
    session: DbSession, *, user_id: UUID, token_hash: bytes, installation_id: UUID
) -> Outcome:
    return await _call(
        session,
        ISSUE_REFRESH_TOKEN,
        user_id=user_id,
        token_hash=token_hash,
        installation_id=installation_id,
    )


async def rotate_refresh_token(
    session: DbSession, *, token_hash: bytes, new_token_hash: bytes, installation_id: UUID
) -> Outcome:
    return await _call(
        session,
        ROTATE_REFRESH_TOKEN,
        token_hash=token_hash,
        new_token_hash=new_token_hash,
        installation_id=installation_id,
    )


async def revoke_tokens(
    session: DbSession,
    *,
    user_id: UUID,
    scope: str,
    reason: str,
    family_id: UUID | None = None,
    keep_family_id: UUID | None = None,
) -> Outcome:
    return await _call(
        session,
        REVOKE_TOKENS,
        user_id=user_id,
        scope=scope,
        reason=reason,
        family_id=family_id,
        keep_family_id=keep_family_id,
    )


async def set_password(
    session: DbSession, *, user_id: UUID, password_hash: str, keep_family_id: UUID | None
) -> None:
    await session.execute(
        SET_PASSWORD, user_id=user_id, password_hash=password_hash, keep_family_id=keep_family_id
    )


async def rehash_password(
    session: DbSession, *, user_id: UUID, old_hash: str, new_hash: str
) -> Outcome:
    return await _call(
        session, REHASH_PASSWORD, user_id=user_id, old_hash=old_hash, new_hash=new_hash
    )


async def link_identity(
    session: DbSession, *, user_id: UUID, provider: str, subject: str, email: str
) -> None:
    await session.execute(
        LINK_IDENTITY, user_id=user_id, provider=provider, subject=subject, email=email
    )


async def store_provider_token(
    session: DbSession, *, user_id: UUID, provider: str, subject: str, token: str
) -> Outcome:
    return await _call(
        session,
        STORE_PROVIDER_TOKEN,
        user_id=user_id,
        provider=provider,
        subject=subject,
        token=token,
    )
