"""The DB layer against a real migrated PostgreSQL 18.6 (naraacare-database), as the app_rw role.

Skipped unless NARAACARE_TEST_DATABASE_URL is set, e.g.
    postgresql+asyncpg://app_rw:local-dev-only-app-rw@localhost:5432/naraacare_test
NARAACARE_TEST_ADMIN_URL (a superuser asyncpg DSN) additionally enables checks that read the
audit tables, which app_rw itself cannot read.
"""

from __future__ import annotations

import os
import secrets
import uuid
from collections.abc import AsyncIterator

import pytest
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.error_catalogue import ErrorCode
from app.core.exceptions import AppError
from app.core.security.request_context import set_request_id
from app.repositories.audit import SecurityEvent, SecurityEventWriter
from app.repositories.base import Database, db_call
from tests.conftest import AppFactory

DB_URL = os.environ.get("NARAACARE_TEST_DATABASE_URL")
ADMIN_URL = os.environ.get("NARAACARE_TEST_ADMIN_URL")
pytestmark = [
    pytest.mark.db,
    pytest.mark.skipif(DB_URL is None, reason="NARAACARE_TEST_DATABASE_URL not set"),
]

PING = db_call("SELECT ops.fn_ping() AS ok")
CREATE_ACCOUNT = db_call(
    "CALL auth.pr_create_account(:email, :password_hash, :installation_id, :code, "
    "NULL, NULL, NULL, NULL)"
)
GET_PROFILE = db_call("SELECT * FROM app.fn_get_profile(:user_id)")
SET_USERNAME = db_call("CALL app.pr_set_username(:user_id, :username)")
USERNAME_AVAILABLE = db_call("SELECT app.fn_username_available(:username) AS available")
ARGON = "$argon2id$v=19$m=16384,t=2,p=1$c2FsdHNhbHQ$aGFzaA"


@pytest.fixture
async def db() -> AsyncIterator[Database]:
    assert DB_URL is not None
    database = Database(create_async_engine(DB_URL, connect_args={"statement_cache_size": 0}))
    yield database
    await database.dispose()


async def _new_account(db: Database) -> uuid.UUID:
    async with db.transaction() as session:
        row = await session.fetch_one(
            CREATE_ACCOUNT,
            email=f"db-{secrets.token_hex(6)}@example.test",
            password_hash=ARGON,
            installation_id=uuid.uuid4(),
            code=f"{secrets.randbelow(10**6):06d}",
        )
    assert row is not None
    assert row["o_status"] == "ok"
    return uuid.UUID(str(row["o_user_id"]))


async def test_ping_through_app_rw(db: Database) -> None:
    async with db.transaction() as session:
        assert await session.fetch_value(PING) == 1


async def test_procedure_inout_values_come_back(db: Database) -> None:
    user_id = await _new_account(db)
    assert user_id.version == 7  # uuidv7() from the database


async def test_actor_is_set_per_transaction(db: Database) -> None:
    user_id = await _new_account(db)
    async with db.transaction(user_id=user_id) as session:
        profile = await session.fetch_one(GET_PROFILE, user_id=user_id)
    assert profile is not None
    assert profile["status"] == "pending_verification"


async def test_other_users_data_maps_to_not_found(db: Database) -> None:
    owner, intruder = await _new_account(db), await _new_account(db)
    with pytest.raises(AppError) as info:
        async with db.transaction(user_id=intruder) as session:
            await session.fetch_one(GET_PROFILE, user_id=owner)
    assert info.value.code is ErrorCode.NOT_FOUND


async def test_no_actor_maps_to_not_found(db: Database) -> None:
    user_id = await _new_account(db)
    with pytest.raises(AppError) as info:
        async with db.transaction() as session:
            await session.fetch_one(GET_PROFILE, user_id=user_id)
    assert info.value.code is ErrorCode.NOT_FOUND


async def test_business_error_detail_maps_to_catalogue_code(db: Database) -> None:
    user_id = await _new_account(db)
    with pytest.raises(AppError) as info:
        async with db.transaction(user_id=user_id) as session:
            await session.fetch_one(SET_USERNAME, user_id=user_id, username="priya.s")
    assert info.value.code is ErrorCode.ONBOARDING_INCOMPLETE


async def test_domain_violation_maps_to_validation_failed(db: Database) -> None:
    user_id = await _new_account(db)
    with pytest.raises(AppError) as info:
        async with db.transaction(user_id=user_id) as session:
            await session.fetch_one(USERNAME_AVAILABLE, username="<script>")
    assert info.value.code is ErrorCode.VALIDATION_FAILED


async def test_run_returns_the_work_result(db: Database) -> None:
    async def work(session: object) -> int:
        from app.repositories.base import DbSession  # noqa: PLC0415

        assert isinstance(session, DbSession)
        return int(await session.fetch_value(PING))

    assert await db.run(work) == 1


@pytest.mark.skipif(ADMIN_URL is None, reason="NARAACARE_TEST_ADMIN_URL not set")
async def test_security_event_writer_persists_without_payload(db: Database) -> None:
    import asyncpg  # noqa: PLC0415

    request_id = uuid.uuid4()
    set_request_id(str(request_id))
    writer = SecurityEventWriter(db)
    writer.start()
    writer.submit(
        SecurityEvent(
            event_type="validation_rejected",
            ip="203.0.113.7",
            request_id=request_id,
            field_name="Profile.Full-Name",
            details={"field_count": 1, "method": "post"},
        )
    )
    await writer.stop()
    assert ADMIN_URL is not None
    conn = await asyncpg.connect(ADMIN_URL)
    try:
        row = await conn.fetchrow(
            "SELECT field_name, details::text AS details FROM audit.security_event "
            "WHERE request_id = $1",
            request_id,
        )
    finally:
        await conn.close()
    assert row is not None
    assert row["field_name"] == "profile.full_name"
    assert row["details"] == '{"method": "post", "field_count": 1}'


def test_readiness_is_ok_with_a_real_database(app_factory: AppFactory) -> None:
    assert DB_URL is not None
    real_db = Database(create_async_engine(DB_URL, connect_args={"statement_cache_size": 0}))
    harness = app_factory(db=real_db)
    response = harness.client.get("/api/v1/health/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "checks": {"database": "ok"}}
