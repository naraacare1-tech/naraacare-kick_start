# 08 — Environment and Configuration

## 1. Principles

- Every project ships `.env.example` with **all** keys and dummy values, plus a README table explaining each key (copied from this document).
- `.env`, `env/*.env` (except examples), `*.pem`, `*.p8`, `*.jks`, `*.keystore`, `google-services.json`, `GoogleService-Info.plist` (non-dev) are in `.gitignore`. gitleaks blocks accidental commits.
- **No secrets, keys, URLs or credentials hard-coded** in source. Defaults in code exist only for non-sensitive tuning values (e.g. page size).
- Backend loads config with **pydantic-settings**; missing required variables or invalid values **abort startup** with a clear message (names only, never values).
- **Production secret manager: the hosting provider's managed secret manager** (vendor-neutral, decision 2026-10-29; chosen with the provider in S17), in the same Indian region, encrypted at rest. Secrets reach the API/worker as environment variables injected by the platform at start (referenced by name in the deployment config), so values never appear in config files, release artifacts or CI logs. Rotation: DB passwords 30 days (scripted: new password in the secret manager, `ALTER ROLE`, rolling restart), JWT signing keys 90 days (dual-key `kid` overlap), field-encryption DEKs 90 days (doc 07 §6.1), blind-index key never rotated without a re-index plan.
- Values differ per environment: `dev` (native installs on the laptop), `staging` and `prod` (separate projects/accounts at the hosting provider). Separate secret managers and master keys, store sandbox vs production, separate Firebase projects, separate Anthropic workspaces.

Legend: **Req** = required (startup fails if missing) · **Secret** = must come from the secret manager in staging/prod.

## 2. `naraacare-backend` (`.env.example`)

| Key | Req | Secret | Example (dummy) | Description |
|---|---|---|---|---|
| `APP_ENV` | ✓ | | `dev` | `dev` / `staging` / `prod`; enables prod-only guards |
| `APP_NAME` | | | `naraacare-api` | service name in logs/traces |
| `APP_VERSION` | | | `0.1.0` | injected at build |
| `LOG_LEVEL` | | | `INFO` | `DEBUG` not allowed when `APP_ENV=prod` (startup check) |
| `API_DOCS_ENABLED` | | | `true` | must be `false` in prod (startup check) |
| `API_DOCS_BASIC_AUTH` | | ✓ | `docs:change-me` | protects docs on staging; format `user:password` |
| `ALLOWED_HOSTS` | ✓ | | `api.dev.naraacare.local,localhost` | Host header allow-list |
| `CORS_ALLOWED_ORIGINS` | | | `` | comma list; empty in prod |
| `MIN_APP_VERSION_ANDROID` / `MIN_APP_VERSION_IOS` | ✓ | | `1.0.0` | force-update threshold |
| `DATABASE_URL` | ✓ | ✓ | `postgresql+asyncpg://app_rw:dummy@localhost:5432/naraacare` | primary (via PgBouncer when deployed), role `app_rw` |
| `DATABASE_REPLICA_URL` | | ✓ | `postgresql+asyncpg://app_readonly:dummy@db-replica.internal:6432/naraacare` | read replica (falls back to primary) |
| `DATABASE_SSL_MODE` | ✓ | | `disable` (dev) / `verify-full` | TLS to DB |
| `DATABASE_SSL_ROOT_CERT` | | | `/etc/ssl/certs/db-provider-ca.pem` | the database provider's CA bundle path |
| `DATABASE_POOL_SIZE` / `DATABASE_MAX_OVERFLOW` | | | `10` / `10` | per task |
| `DATABASE_STATEMENT_TIMEOUT_MS` | | | `5000` | |
| `REDIS_URL` | ✓ | ✓ | `redis://localhost:6379/0` | rate limit, cache, queue, pub/sub (`rediss://` with TLS + AUTH outside dev) |
| `JWT_ISSUER` / `JWT_AUDIENCE` | ✓ | | `https://api.naraacare.app` / `naraacare-mobile` | |
| `JWT_PRIVATE_KEY_PEM` | ✓ (staging/prod) | ✓ | `(Ed25519 PKCS#8 PEM)` | access-token signing key from `tools/new_jwt_key.py`; empty in dev = ephemeral key generated at start-up |
| `JWT_PUBLIC_KEYS_JSON` | ✓ (staging/prod) | ✓ | `{"k1":"-----BEGIN PUBLIC KEY-----…"}` | verification keys by `kid` (old key kept 15 min after rotation) |
| `JWT_ACTIVE_KID` | ✓ | | `k1` | |
| `ACCESS_TOKEN_TTL_SECONDS` | | | `900` | |
| `REFRESH_TOKEN_TTL_DAYS` | | | `60` | sliding |
| `LINK_TOKEN_TTL_SECONDS` | | | `600` | lifetime of the Google/Apple link token (S05) |
| `ARGON2_MEMORY_KIB` / `ARGON2_TIME_COST` / `ARGON2_PARALLELISM` | | | `65536` / `3` / `2` | |
| `OTP_TTL_SECONDS` / `OTP_MAX_ATTEMPTS` / `OTP_RESEND_COOLDOWN_SECONDS` / `OTP_MAX_SENDS_PER_HOUR` | | | `300` / `3` / `30` / `5` | DOC values |
| `LOCKOUT_THRESHOLD` / `LOCKOUT_WINDOW_SECONDS` | | | `5` / `900` | |
| `FIELD_ENCRYPTION_MASTER_KEY_B64` | ✓ (staging/prod) | ✓ | `(32 random bytes, base64)` | master key that wraps the DEKs; made with `tools/new_dek.py --master-key`; start-up fails if missing outside dev |
| `FIELD_ENCRYPTION_DEKS_JSON` | ✓ (staging/prod) | ✓ | `{"1":"AV3k…"}` | wrapped data keys by key id, made with `tools/new_dek.py --dek-id N`; unwrapped once at start-up (S04) |
| `FIELD_ENCRYPTION_ACTIVE_KEY_ID` | ✓ (staging/prod) | | `1` | DEK used for new values; older ids stay for decryption (rotation) (S04) |
| `FIELD_ENCRYPTION_LOCAL_KEY_B64` | ✓ (dev only) | ✓ | `ZHVtbXlrZXlkdW1teWtleWR1bW15a2V5ZHVtbXk=` | 32-byte key for local dev; startup fails if set in prod |
| `BLIND_INDEX_KEY_B64` | ✓ | ✓ | `ZHVtbXk...` | HMAC key for blind indexes; at least 32 bytes (start-up fails otherwise) |
| `STORAGE_BACKEND` | | | `filesystem` | object storage implementation; `filesystem` in dev, the provider's adapter (added in S17) elsewhere |
| `STORAGE_ROOT_DIR` | | | `var/storage` | dev only: folder holding the containers |
| `STORAGE_CONTAINER_REPORTS` / `STORAGE_CONTAINER_EXPORTS` / `STORAGE_CONTAINER_ATTACHMENTS` | ✓ | | `reports` | private containers (buckets), encrypted at rest |
| `STORAGE_SIGNED_URL_TTL_SECONDS` | | | `300` | lifetime of download links |
| `EMAIL_BACKEND` | | | `outbox` (dev) / `smtp` | `outbox` writes `.eml` files to `EMAIL_OUTBOX_DIR` (dev only; never logged); `smtp` required outside dev |
| `EMAIL_OUTBOX_DIR` | | | `var/outbox` | dev only |
| `EMAIL_FROM_ADDRESS` | ✓ | | `no-reply@mail.naraacare.app` | |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USERNAME` | ✓ outside dev (host) | | `smtp.example.invalid` / `587` / `naraacare` | any transactional email provider; STARTTLS required |
| `SMTP_PASSWORD` | | ✓ | `dummy` | SMTP credential |
| `SUPPORT_INBOX_ADDRESS` | ✓ | | `support@naraacare.com` | ticket forwarding (user queries) |
| `SUPPORT_CONTACT_EMAIL` | | | `support@naraacare.com` | public address on the Help screen; empty = inbox |
| `ERROR_ALERT_EMAIL` | | | `info@naraacare.com` | unhandled API errors (500) and failed jobs are emailed here: plain text, no user data, throttled (1 per error per 15 min, 30/h); empty = off. Also carries the owner alerts (OTP email, Google/Apple sign-in, AI credits, Rin health, payments, reports, day jobs): `app/integrations/ops_monitor.py` |
| `AI_ACCOUNT_MONTHLY_BUDGET_INR` | | | empty | our OpenAI spend limit per month; alert email at 80% and 95% (empty = no budget alerts) |
| `GOOGLE_OAUTH_CLIENT_IDS` | ✓ | | `123-android.apps.googleusercontent.com,123-ios…` | accepted `aud` values |
| `GOOGLE_JWKS_URL` / `APPLE_JWKS_URL` | ✓ | | `https://www.googleapis.com/oauth2/v3/certs` / `https://appleid.apple.com/auth/keys` | provider public keys for ID-token verification (https only) |
| `APPLE_TOKEN_URL` | ✓ | | `https://appleid.apple.com/auth/token` | Sign in with Apple code exchange (revocation token) |
| `APPLE_BUNDLE_ID` / `APPLE_SERVICE_ID` | ✓ | | `com.naraacare.app.dev` | Sign in with Apple audience |
| `APPLE_TEAM_ID` / `APPLE_SIWA_KEY_ID` / `APPLE_SIWA_PRIVATE_KEY_P8` | ✓ | ✓ (key) | `ABCDE12345` / `KEY123` / `-----BEGIN PRIVATE KEY-----dummy` | token exchange/revocation |
| `GOOGLE_PLAY_PACKAGE_NAME` | ✓ | | `com.naraacare.app.dev` | |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | ✓ | ✓ | `{"type":"service_account",...dummy}` | Play Developer API |
| `GOOGLE_RTDN_PUSH_AUDIENCE` / `GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL` | ✓ | | `https://api.dev.naraacare.app/api/v1/billing/webhooks/google` / `rtdn@proj.iam.gserviceaccount.com` | Google Pub/Sub push-token verification |
| `APP_STORE_ISSUER_ID` / `APP_STORE_KEY_ID` / `APP_STORE_PRIVATE_KEY_P8` | ✓ | ✓ (key) | dummy | App Store Server API |
| `APP_STORE_ENVIRONMENT` | ✓ | | `Sandbox` | `Sandbox` / `Production` |
| `APPLE_ROOT_CA_PATHS` | ✓ | | `certs/AppleRootCA-G3.cer` | JWS verification |
| `FCM_SERVICE_ACCOUNT_JSON` | ✓ | ✓ | dummy | FCM HTTP v1 service-account key (S09: a non-`service_account` value disables push in dev; refused in staging/prod) |
| `FCM_API_BASE_URL` | | | `https://fcm.googleapis.com` | FCM HTTP v1 base URL (https only) |
| `GOOGLE_OAUTH_TOKEN_URL` | | | `https://oauth2.googleapis.com/token` | token endpoint for the FCM service account (https only; never taken from the key file) |
| `GOOGLE_PLAY_API_BASE_URL` | | | `https://androidpublisher.googleapis.com` | Play Developer API (S11, https only) |
| `APP_STORE_API_BASE_URL`, `APP_STORE_SANDBOX_API_BASE_URL` | | | Apple's production / sandbox URLs | App Store Server API for reconcile (S11) |
| `PLAY_MANAGE_SUBSCRIPTIONS_URL`, `APP_STORE_MANAGE_SUBSCRIPTIONS_URL` | | | store pages | "Manage / cancel" links returned by `GET /billing/subscription` (S11) |
| `ANTHROPIC_API_KEY` | ✓ (if `RIN_ENABLED`) | ✓ | `sk-ant-dummy` | Claude API |
| `RIN_ENABLED` | | | `true` | kill switch |
| `RIN_MODEL` | | | `claude-opus-5-5` | model id (OQ-37) |
| `RIN_EFFORT` | | | `low` | `output_config.effort` for chat |
| `RIN_DAILY_TOKEN_ALLOWANCE` | | | `100000` | per STAR user/day (placeholder) |
| `RIN_MAX_OUTPUT_TOKENS` | | | `2048` | per reply |
| `OPEN_FOOD_FACTS_BASE_URL` / `OPEN_FOOD_FACTS_USER_AGENT` | | | `https://world.openfoodfacts.org` / `NaraaCare/0.1 (support@naraacare.app)` | barcode fallback |
| `REFERRAL_LINK_DOMAIN` | ✓ | | `naraacare.app` | OQ-39 |
| `INVITE_LINK_TTL_DAYS` | | | `7` | |
| `RATE_LIMIT_DEFAULT_PER_MIN_USER` / `_IP` | | | `300` / `600` | |
| `MAX_BODY_BYTES` / `MAX_UPLOAD_BYTES` | | | `1048576` / `10485760` | |
| `SENTRY_DSN` | | ✓ | `https://dummy@o0.ingest.sentry.io/0` | empty disables |
| `SENTRY_TRACES_SAMPLE_RATE` | | | `0.1` | |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | | | `http://otel-collector:4317` | |
| `WORKER_CONCURRENCY` | | | `10` | taskiq worker max async tasks |
| `FEATURE_FLAGS_SOURCE` | | | `db` | `db` / `env` |

## 3. `naraacare-database` (`.env.example`, used by Flyway and the local/CI tools)

| Key | Req | Secret | Example | Description |
|---|---|---|---|---|
| `PGHOST` / `PGPORT` / `PGDATABASE` | ✓ | | `localhost` / `5432` / `naraacare` | target |
| `FLYWAY_URL` | ✓ | | `jdbc:postgresql://localhost:5432/naraacare?sslmode=disable` | `sslmode=verify-full` outside dev |
| `FLYWAY_USER` / `FLYWAY_PASSWORD` | ✓ | ✓ | `migration_owner` / `dummy` | migration role |
| `FLYWAY_LOCATIONS` | ✓ | | `filesystem:migrations,filesystem:seed,filesystem:functions,filesystem:procedures,filesystem:views,filesystem:triggers` | |
| `FLYWAY_PLACEHOLDERS_APP_RW_PASSWORD` | ✓ (first deploy) | ✓ | `dummy` | role creation; prod rotates them via the secret manager afterwards |
| `FLYWAY_PLACEHOLDERS_APP_WORKER_PASSWORD` / `_APP_READONLY_PASSWORD` / `_REPORTING_PASSWORD` | ✓ | ✓ | `dummy` | |
| `FLYWAY_VALIDATE_MIGRATION_NAMING` | | | `true` | |
| `FLYWAY_CLEAN_DISABLED` | ✓ | | `true` | never allow `clean` outside local |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | ✓ (local/CI only) | | `postgres` / `local-dev-only` | local superuser: bootstrap, test databases, pgTAP |
| `PGTAP_DATABASE` | | | `naraacare_test` | test DB |

## 4. `naraacare-mobile`

Mobile config is **non-secret only** and loaded per flavor with `flutter run --flavor dev -t lib/main_dev.dart --dart-define-from-file=env/dev.env` (Flutter ≥ 3.19 accepts `.env` format; JSON `env/dev.json` is the fallback if needed). `env/*.env` files are git-ignored; `.env.example` is committed; CI writes the file from repository variables (not secrets, because none are secret).

| Key | Example | Description |
|---|---|---|
| `ENV_NAME` | `dev` | `dev` / `staging` / `prod`; shown in a debug ribbon (non-prod) |
| `API_BASE_URL` | `https://api.dev.naraacare.app/api/v1` | must be `https://` (startup assert) |
| `WS_BASE_URL` | `wss://api.dev.naraacare.app/api/v1/ws` | |
| `CERT_PINS` | `sha256/AAAA…=,sha256/BBBB…=` | leaf-certificate SPKI pins (current + backup key, OQ-66); empty = pinning off, allowed in dev only |
| `SENTRY_DSN` | `https://dummy@o0.ingest.sentry.io/1` | public DSN; scrubbing on |
| `GOOGLE_SERVER_CLIENT_ID` | `123-web.apps.googleusercontent.com` | for `google_sign_in` ID token audience |
| `APPLE_SERVICE_ID` | `com.naraacare.app.dev.siwa` | Android Apple sign-in web flow |
| `APPLE_REDIRECT_URI` | `https://api.dev.naraacare.app/api/v1/auth/oauth/apple/callback` | Android web flow |
| `REFERRAL_LINK_DOMAIN` | `naraacare.app` | deep-link host allow-list |
| `TERMS_URL` / `PRIVACY_URL` | `https://naraacare.app/terms` | fallback if policy API is down |
| `SUPPORT_EMAIL` | `support@naraacare.com` | |
| `FEATURE_FLAGS` | `voice_logging=true,barcode=true` | UI-only toggles; server still enforces |
| `STORE_PRODUCT_IDS` | `star_monthly,star_yearly` | in-app purchase product ids |
| `LOG_HTTP` | `false` | must be `false` for staging/prod builds (assert) |

Per-flavor native identifiers (in Gradle / Xcode config, not env):

| Flavor | Android applicationId | iOS bundle ID | Firebase project |
|---|---|---|---|
| dev | `com.naraacare.app.dev` | `com.naraacare.app.dev` | `naraacare-dev` |
| staging | `com.naraacare.app.staging` | `com.naraacare.app.staging` | `naraacare-staging` |
| prod | `com.naraacare.app` | `com.naraacare.app` | `naraacare-prod` |

`google-services.json` / `GoogleService-Info.plist` per flavor are not secret but are environment-specific. They are kept out of git for staging/prod and injected by CI.

Signing material (Android upload keystore + password, iOS distribution certificate/profiles, App Store Connect API key) lives in GitHub Actions encrypted secrets / Fastlane Match (encrypted git repo). It is never in the app repo.

## 5. CI/CD secrets (GitHub Actions)

| Secret | Repo | Use |
|---|---|---|
| `DEPLOY_CREDENTIALS_STAGING` / `_PROD` | backend, database | short-lived deploy identity for the hosting provider (workload identity federation from GitHub OIDC where the provider supports it, so no long-lived keys); defined in S17 |
| `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | mobile | release signing |
| `PLAY_SERVICE_ACCOUNT_JSON` | mobile | Fastlane supply upload |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `MATCH_PASSWORD`, `MATCH_GIT_URL` | mobile | iOS signing/upload |
| `SENTRY_AUTH_TOKEN` | mobile, backend | symbol/source-map upload |
| `DATABASE_REPO_READ_TOKEN` (+ repository variable `DATABASE_REF`, default `main`) | backend | read-only checkout of naraacare-database so CI migrates a runner-installed PostgreSQL for the integration tests |

## 6. Startup validation (backend)

```python
class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="forbid", case_sensitive=True)
    APP_ENV: Literal["dev", "staging", "prod"]
    DATABASE_URL: SecretStr
    JWT_PRIVATE_KEY_PEM: SecretStr
    ...
    @model_validator(mode="after")
    def prod_guards(self) -> "Settings":
        if self.APP_ENV == "prod":
            assert not self.API_DOCS_ENABLED, "API_DOCS_ENABLED must be false in prod"
            assert self.LOG_LEVEL != "DEBUG"
            assert self.FIELD_ENCRYPTION_LOCAL_KEY_B64 is None
            assert self.DATABASE_SSL_MODE == "verify-full"
        return self
```
All secrets are `SecretStr` (masked in repr/logs).
