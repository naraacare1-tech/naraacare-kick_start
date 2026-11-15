from __future__ import annotations

import json
from pathlib import Path

import pytest

from app.core.config import Settings, SettingsLoadError, load_settings
from tests.conftest import MakeSettings, SetEnv

_SERVICE_ACCOUNT = json.dumps(
    {
        "type": "service_account",
        "project_id": "test-project",
        "client_email": "test@test-project.iam.gserviceaccount.com",
        "private_key": "test-private-key",
    }
)

PROD_OK: dict[str, str | None] = {
    "FCM_SERVICE_ACCOUNT_JSON": _SERVICE_ACCOUNT,
    "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON": _SERVICE_ACCOUNT,
    "APP_ENV": "prod",
    "API_DOCS_ENABLED": "false",
    "JWT_PRIVATE_KEY_PEM": "test-private-key",
    "JWT_PUBLIC_KEYS_JSON": '{"k1": "test-public-key"}',
    "DATABASE_SSL_MODE": "verify-full",
    "APP_STORE_ENVIRONMENT": "Production",
    "EMAIL_BACKEND": "smtp",
    "SMTP_HOST": "smtp.example.invalid",
}


def test_example_env_is_valid(make_settings: MakeSettings) -> None:
    settings = make_settings()
    assert settings.APP_ENV == "dev"
    assert settings.ALLOWED_HOSTS == ["localhost", "127.0.0.1", "10.0.2.2"]


def test_example_env_documents_every_setting(example_env: dict[str, str]) -> None:
    fields = set(Settings.model_fields)
    documented = set(example_env)
    assert fields - documented == set(), "settings missing from .env.example"
    assert documented - fields == set(), ".env.example keys unknown to Settings"


def test_missing_required_variable_fails_fast_with_name_only(set_env: SetEnv) -> None:
    set_env(DATABASE_URL=None)
    with pytest.raises(SettingsLoadError) as exc:
        load_settings()
    message = str(exc.value)
    assert "DATABASE_URL" in message
    # Values of other (secret) settings must never be echoed.
    assert "local-dev-only" not in message
    assert "dummy-not-a-key" not in message


def test_invalid_value_is_reported_without_the_value(set_env: SetEnv) -> None:
    set_env(APP_ENV="super-secret-typo")
    with pytest.raises(SettingsLoadError) as exc:
        load_settings()
    assert "APP_ENV" in str(exc.value)
    assert "super-secret-typo" not in str(exc.value)


@pytest.mark.parametrize(
    ("overrides", "expected"),
    [
        ({"API_DOCS_ENABLED": "true"}, "API_DOCS_ENABLED must be false in prod"),
        ({"LOG_LEVEL": "DEBUG"}, "LOG_LEVEL=DEBUG is not allowed in prod"),
        ({"DATABASE_SSL_MODE": "disable"}, "DATABASE_SSL_MODE must be verify-full"),
        ({"CORS_ALLOWED_ORIGINS": "https://evil.example"}, "CORS_ALLOWED_ORIGINS must be empty"),
        ({"APP_STORE_ENVIRONMENT": "Sandbox"}, "APP_STORE_ENVIRONMENT must be Production"),
        ({"EMAIL_BACKEND": "outbox"}, "EMAIL_BACKEND must be smtp"),
        (
            {"JWT_PRIVATE_KEY_PEM": None},
            "JWT_PRIVATE_KEY_PEM and JWT_PUBLIC_KEYS_JSON are required",
        ),
        (
            {"APPLE_JWKS_URL": "http://appleid.apple.com/auth/keys"},
            "APPLE_JWKS_URL must be an https",
        ),
        ({"SMTP_HOST": None}, "EMAIL_BACKEND must be smtp"),
    ],
)
def test_prod_guards(set_env: SetEnv, overrides: dict[str, str | None], expected: str) -> None:
    set_env(**{**PROD_OK, **overrides})
    with pytest.raises(SettingsLoadError, match=expected):
        load_settings()


def test_valid_prod_configuration_loads(make_settings: MakeSettings, tmp_path: Path) -> None:
    # Tests run from tmp_path, so the relative APPLE_ROOT_CA_PATHS resolves here.
    cert = tmp_path / "certs" / "AppleRootCA-G3.cer"
    cert.parent.mkdir()
    cert.write_bytes(b"test-certificate")
    assert make_settings(**PROD_OK).APP_ENV == "prod"


def test_staging_docs_need_basic_auth(set_env: SetEnv) -> None:
    set_env(**{**PROD_OK, "APP_ENV": "staging", "API_DOCS_ENABLED": "true"})
    with pytest.raises(SettingsLoadError, match="API_DOCS_BASIC_AUTH is required"):
        load_settings()


def test_docs_credential_must_be_user_and_password(set_env: SetEnv) -> None:
    set_env(
        **{**PROD_OK, "APP_ENV": "staging", "API_DOCS_ENABLED": "true"},
        API_DOCS_BASIC_AUTH="no-colon",
    )
    with pytest.raises(SettingsLoadError, match="API_DOCS_BASIC_AUTH must be user:password"):
        load_settings()


def test_empty_value_counts_as_unset(make_settings: MakeSettings) -> None:
    settings = make_settings(API_DOCS_BASIC_AUTH="", DATABASE_REPLICA_URL="")
    assert settings.API_DOCS_BASIC_AUTH is None
    assert settings.DATABASE_REPLICA_URL is None


def test_rin_requires_api_key(set_env: SetEnv) -> None:
    set_env(RIN_ENABLED="true", OPENAI_API_KEY=None)
    with pytest.raises(SettingsLoadError, match="OPENAI_API_KEY is required"):
        load_settings()
