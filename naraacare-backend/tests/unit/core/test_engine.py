"""Engine settings: PgBouncer-safe statements, TLS modes, replica (no connection is made)."""

from __future__ import annotations

import ssl

import pytest

from app.db.engine import _connect_args, _ssl_arg, create_engines
from tests.conftest import MakeSettings


def test_disable_means_no_tls() -> None:
    assert _ssl_arg("disable", None) is False


def test_verify_full_checks_certificate_and_host() -> None:
    context = _ssl_arg("verify-full", None)
    assert isinstance(context, ssl.SSLContext)
    assert context.check_hostname
    assert context.verify_mode == ssl.CERT_REQUIRED


@pytest.mark.parametrize(
    ("mode", "verify"), [("require", ssl.CERT_NONE), ("verify-ca", ssl.CERT_REQUIRED)]
)
def test_weaker_modes(mode: str, verify: ssl.VerifyMode) -> None:
    context = _ssl_arg(mode, None)
    assert isinstance(context, ssl.SSLContext)
    assert not context.check_hostname
    assert context.verify_mode == verify


def test_pgbouncer_safe_connect_args(make_settings: MakeSettings) -> None:
    args = _connect_args(make_settings())
    assert args["statement_cache_size"] == 0
    first, second = args["prepared_statement_name_func"](), args["prepared_statement_name_func"]()
    assert first != second  # unique names: no clash across pooled server connections
    assert args["server_settings"] == {"application_name": "naraacare-api"}


async def test_primary_and_optional_replica(make_settings: MakeSettings) -> None:
    primary, replica = create_engines(make_settings())
    assert replica is None
    await primary.dispose()
    primary, replica = create_engines(
        make_settings(
            DATABASE_REPLICA_URL="postgresql+asyncpg://app_readonly:x@replica:5432/naraacare"
        )
    )
    assert replica is not None
    assert primary.pool.size() == 10  # type: ignore[attr-defined]
    await primary.dispose()
    await replica.dispose()
