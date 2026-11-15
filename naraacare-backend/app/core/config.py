"""Application settings (doc 08 §2).

Loaded once at startup from environment variables (and `.env` in local development).
Startup fails fast with a list of offending variable *names* — values are never printed,
because pydantic's default error text can echo inputs (which may be secrets).
"""

from __future__ import annotations

import ipaddress
import json
from decimal import Decimal
from pathlib import Path
from typing import Annotated, Literal

from pydantic import Field, SecretStr, ValidationError, field_validator, model_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

CommaList = Annotated[list[str], NoDecode]


class SettingsLoadError(RuntimeError):
    """Raised when configuration is missing or invalid. Message contains names only."""


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="forbid",
        case_sensitive=True,
        env_ignore_empty=True,  # `KEY=` in .env means "unset", not an empty secret
        hide_input_in_errors=True,
    )

    # --- app
    APP_ENV: Literal["dev", "staging", "prod"]
    APP_NAME: str = "naraacare-api"
    APP_VERSION: str = "0.1.0"
    LOG_LEVEL: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"
    API_DOCS_ENABLED: bool = False
    API_DOCS_BASIC_AUTH: SecretStr | None = None
    ALLOWED_HOSTS: CommaList
    CORS_ALLOWED_ORIGINS: CommaList = Field(default_factory=list)
    # Staff routes (/admin/*) answer only from these networks (CIDR list, doc 07 SEC-1.5). Empty =
    # staff routes closed everywhere (they answer 404).
    STAFF_IP_ALLOWLIST: CommaList = Field(default_factory=list)

    # --- database
    DATABASE_URL: SecretStr
    DATABASE_REPLICA_URL: SecretStr | None = None
    DATABASE_SSL_MODE: Literal["disable", "require", "verify-ca", "verify-full"]
    DATABASE_SSL_ROOT_CERT: str | None = None
    DATABASE_POOL_SIZE: int = Field(default=10, ge=1, le=100)
    DATABASE_MAX_OVERFLOW: int = Field(default=10, ge=0, le=100)

    # --- redis: background worker queue only (the API keeps rate limits in memory, no cache)
    REDIS_URL: SecretStr | None = None

    # --- tokens
    JWT_ISSUER: str
    JWT_AUDIENCE: str
    # Ed25519 signing key (PKCS#8 PEM) and {"kid": "<public key PEM>"} for verification. Optional in
    # dev only: without them an ephemeral key is generated at start-up (tokens die on restart).
    JWT_PRIVATE_KEY_PEM: SecretStr | None = None
    JWT_PUBLIC_KEYS_JSON: SecretStr | None = None
    JWT_ACTIVE_KID: str
    ACCESS_TOKEN_TTL_SECONDS: int = Field(default=900, ge=60, le=3600)
    REFRESH_TOKEN_TTL_DAYS: int = Field(default=60, ge=1, le=365)
    LINK_TOKEN_TTL_SECONDS: int = Field(default=600, ge=60, le=1800)

    # --- password hashing (OTP rules live in the auth service, lockout in the database)
    ARGON2_MEMORY_KIB: int = Field(default=65536, ge=19456)
    ARGON2_TIME_COST: int = Field(default=3, ge=2)
    ARGON2_PARALLELISM: int = Field(default=2, ge=1)

    # --- object storage (vendor-neutral; the hosting provider's adapter is added in Session 17)
    STORAGE_ROOT_DIR: str = "var/storage"
    STORAGE_CONTAINER_REPORTS: str
    STORAGE_CONTAINER_ATTACHMENTS: str

    # --- email (SMTP works with any transactional email provider; dev writes to an outbox folder)
    EMAIL_BACKEND: Literal["outbox", "smtp"] = "smtp"
    EMAIL_OUTBOX_DIR: str = "var/outbox"
    EMAIL_FROM_ADDRESS: str
    SMTP_HOST: str | None = None
    SMTP_PORT: int = Field(default=587, ge=1, le=65535)
    SMTP_USERNAME: str | None = None
    SMTP_PASSWORD: SecretStr | None = None
    SUPPORT_INBOX_ADDRESS: str
    # Help & Support contact card (S14). The public address defaults to the inbox; the phone line is
    # shown to STAR users only and is hidden when unset.
    SUPPORT_CONTACT_EMAIL: str | None = None
    SUPPORT_EMAIL_RESPONSE: str | None = "Expected response: 4-6 hours"
    SUPPORT_PHONE: str | None = Field(default=None, pattern=r"^\+[0-9 ]{8,20}$")
    SUPPORT_PHONE_HOURS: str | None = "Available: 9 AM - 6 PM IST"

    # --- identity providers
    GOOGLE_OAUTH_CLIENT_IDS: CommaList
    APPLE_BUNDLE_ID: str
    APPLE_SERVICE_ID: str
    APPLE_TEAM_ID: str
    APPLE_SIWA_KEY_ID: str
    APPLE_SIWA_PRIVATE_KEY_P8: SecretStr
    GOOGLE_JWKS_URL: str
    APPLE_JWKS_URL: str
    APPLE_TOKEN_URL: str
    APPLE_REVOKE_URL: str | None = None  # S15: token revocation at account deletion

    # --- stores
    GOOGLE_PLAY_PACKAGE_NAME: str
    GOOGLE_PLAY_SERVICE_ACCOUNT_JSON: SecretStr
    GOOGLE_RTDN_PUSH_AUDIENCE: str
    GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL: str
    APP_STORE_ISSUER_ID: str
    APP_STORE_KEY_ID: str
    APP_STORE_PRIVATE_KEY_P8: SecretStr
    APP_STORE_ENVIRONMENT: Literal["Sandbox", "Production"]
    APPLE_ROOT_CA_PATHS: CommaList
    GOOGLE_PLAY_API_BASE_URL: str = "https://androidpublisher.googleapis.com"
    APP_STORE_API_BASE_URL: str = "https://api.storekit.itunes.apple.com"
    APP_STORE_SANDBOX_API_BASE_URL: str = "https://api.storekit-sandbox.itunes.apple.com"
    PLAY_MANAGE_SUBSCRIPTIONS_URL: str = "https://play.google.com/store/account/subscriptions"
    APP_STORE_MANAGE_SUBSCRIPTIONS_URL: str = "https://apps.apple.com/account/subscriptions"

    # --- push (FCM HTTP v1; the OAuth token URL comes from here, never from the key file)
    FCM_SERVICE_ACCOUNT_JSON: SecretStr
    FCM_API_BASE_URL: str = "https://fcm.googleapis.com"
    GOOGLE_OAUTH_TOKEN_URL: str = "https://oauth2.googleapis.com/token"  # noqa: S105  # nosec B105

    # --- Rin AI and the other AI features (owner 2026-11-07: OpenAI GPT-5 mini, Rs 10 per user
    # per month across all AI features; Rin pauses until the next local month when it is used up)
    RIN_ENABLED: bool = True
    OPENAI_API_KEY: SecretStr | None = None
    RIN_MODEL: str = "gpt-5-mini"
    RIN_EFFORT: Literal["minimal", "low", "medium", "high"] = "low"
    RIN_MAX_OUTPUT_TOKENS: int = Field(default=2048, ge=256, le=16000)
    RIN_MONTHLY_BUDGET_INR: Decimal = Field(default=Decimal(10), ge=0)
    # The model's list prices (USD per 1M tokens) and the exchange rate used to cost each call.
    # Update them when OpenAI's prices or the rate change; they are not secrets.
    AI_PRICE_INPUT_USD_PER_MTOK: Decimal = Field(default=Decimal("0.25"), ge=0)
    AI_PRICE_CACHED_INPUT_USD_PER_MTOK: Decimal = Field(default=Decimal("0.025"), ge=0)
    AI_PRICE_OUTPUT_USD_PER_MTOK: Decimal = Field(default=Decimal("2.00"), ge=0)
    AI_USD_TO_INR: Decimal = Field(default=Decimal(88), gt=0)
    # Lower model when OUR OpenAI account is rate-limited or the main model fails (owner
    # 2026-11-11). Empty = no fallback. Its own prices, so the per-user cap still counts it right.
    # When the account has no credits left every OpenAI model is refused: Rin then answers in the
    # free basic mode (app/domain/ai/basic_rin.py) instead.
    RIN_FALLBACK_MODEL: str = "gpt-5-nano"
    AI_FALLBACK_PRICE_INPUT_USD_PER_MTOK: Decimal = Field(default=Decimal("0.05"), ge=0)
    AI_FALLBACK_PRICE_CACHED_INPUT_USD_PER_MTOK: Decimal = Field(default=Decimal("0.005"), ge=0)
    AI_FALLBACK_PRICE_OUTPUT_USD_PER_MTOK: Decimal = Field(default=Decimal("0.40"), ge=0)

    # --- misc integrations
    OPEN_FOOD_FACTS_BASE_URL: str = "https://world.openfoodfacts.org"
    OPEN_FOOD_FACTS_USER_AGENT: str = "NaraaCare/0.1 (support@naraacare.app)"
    REFERRAL_LINK_DOMAIN: str

    # --- limits
    MAX_BODY_BYTES: int = 1_048_576
    MAX_UPLOAD_BYTES: int = 10_485_760

    # --- workers
    WORKER_CONCURRENCY: int = Field(default=10, ge=1, le=100)

    @field_validator(
        "ALLOWED_HOSTS",
        "CORS_ALLOWED_ORIGINS",
        "GOOGLE_OAUTH_CLIENT_IDS",
        "APPLE_ROOT_CA_PATHS",
        "STAFF_IP_ALLOWLIST",
        mode="before",
    )
    @classmethod
    def _split_commas(cls, value: object) -> object:
        if isinstance(value, str):
            return [item.strip() for item in value.split(",") if item.strip()]
        return value

    @field_validator("STAFF_IP_ALLOWLIST")
    @classmethod
    def _cidrs(cls, value: list[str]) -> list[str]:
        for item in value:
            ipaddress.ip_network(item, strict=False)  # ValueError -> named in the load error
        return value

    @model_validator(mode="after")
    def _environment_guards(self) -> Settings:
        checks: list[tuple[bool, str]] = [
            (not self.ALLOWED_HOSTS, "ALLOWED_HOSTS must not be empty"),
            (
                self.RIN_ENABLED and self.OPENAI_API_KEY is None,
                "OPENAI_API_KEY is required when RIN_ENABLED=true",
            ),
        ]
        checks += [
            (not url.startswith("https://"), f"{name} must be an https:// URL")
            for name, url in (
                ("GOOGLE_JWKS_URL", self.GOOGLE_JWKS_URL),
                ("APPLE_JWKS_URL", self.APPLE_JWKS_URL),
                ("APPLE_TOKEN_URL", self.APPLE_TOKEN_URL),
                ("FCM_API_BASE_URL", self.FCM_API_BASE_URL),
                ("GOOGLE_OAUTH_TOKEN_URL", self.GOOGLE_OAUTH_TOKEN_URL),
                ("GOOGLE_PLAY_API_BASE_URL", self.GOOGLE_PLAY_API_BASE_URL),
                ("APP_STORE_API_BASE_URL", self.APP_STORE_API_BASE_URL),
                ("APP_STORE_SANDBOX_API_BASE_URL", self.APP_STORE_SANDBOX_API_BASE_URL),
                ("PLAY_MANAGE_SUBSCRIPTIONS_URL", self.PLAY_MANAGE_SUBSCRIPTIONS_URL),
                ("APP_STORE_MANAGE_SUBSCRIPTIONS_URL", self.APP_STORE_MANAGE_SUBSCRIPTIONS_URL),
            )
        ]
        if self.APP_ENV != "dev":
            checks += self._deployed_checks()
        if self.APP_ENV == "prod":
            checks += self._prod_checks()
        problems = [message for failed, message in checks if failed]
        if problems:
            raise ValueError("; ".join(problems))
        return self

    def _deployed_checks(self) -> list[tuple[bool, str]]:
        """Rules for every deployed environment (staging and prod)."""
        return [
            (
                self.JWT_PRIVATE_KEY_PEM is None or self.JWT_PUBLIC_KEYS_JSON is None,
                "JWT_PRIVATE_KEY_PEM and JWT_PUBLIC_KEYS_JSON are required outside dev",
            ),
            (
                self.DATABASE_SSL_MODE != "verify-full",
                "DATABASE_SSL_MODE must be verify-full outside dev",
            ),
            (
                self.EMAIL_BACKEND != "smtp" or self.SMTP_HOST is None,
                "EMAIL_BACKEND must be smtp with SMTP_HOST set outside dev",
            ),
            (
                self.API_DOCS_ENABLED and self.API_DOCS_BASIC_AUTH is None,
                "API_DOCS_BASIC_AUTH is required when docs are enabled on staging",
            ),
            (
                self.API_DOCS_BASIC_AUTH is not None
                and ":" not in self.API_DOCS_BASIC_AUTH.get_secret_value(),
                "API_DOCS_BASIC_AUTH must be user:password",
            ),
            (
                not _is_service_account(self.FCM_SERVICE_ACCOUNT_JSON.get_secret_value()),
                "FCM_SERVICE_ACCOUNT_JSON must be a service-account key outside dev",
            ),
            (
                not _is_service_account(self.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON.get_secret_value()),
                "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON must be a service-account key outside dev",
            ),
            (
                not self.APPLE_ROOT_CA_PATHS
                or not all(Path(p).is_file() for p in self.APPLE_ROOT_CA_PATHS),
                "APPLE_ROOT_CA_PATHS must point to the Apple root certificate files outside dev",
            ),
        ]

    def _prod_checks(self) -> list[tuple[bool, str]]:
        return [
            (self.API_DOCS_ENABLED, "API_DOCS_ENABLED must be false in prod"),
            (self.LOG_LEVEL == "DEBUG", "LOG_LEVEL=DEBUG is not allowed in prod"),
            (bool(self.CORS_ALLOWED_ORIGINS), "CORS_ALLOWED_ORIGINS must be empty in prod"),
            (
                self.APP_STORE_ENVIRONMENT != "Production",
                "APP_STORE_ENVIRONMENT must be Production in prod",
            ),
        ]


def load_settings() -> Settings:
    """Load settings or raise SettingsLoadError listing variable names (never values)."""
    try:
        return Settings()  # values come from the environment / .env
    except ValidationError as exc:
        lines = []
        for err in exc.errors(include_input=False, include_url=False):
            name = ".".join(str(part) for part in err["loc"]) or "settings"
            lines.append(f"  - {name}: {err['msg']}")
        raise SettingsLoadError("Invalid configuration:\n" + "\n".join(lines)) from None


def _is_service_account(raw: str) -> bool:
    """A Google service-account key file (push is disabled in dev without one)."""
    try:
        data = json.loads(raw)
    except ValueError:
        return False
    return (
        isinstance(data, dict)
        and data.get("type") == "service_account"
        and all(isinstance(data.get(k), str) for k in ("project_id", "client_email", "private_key"))
    )
