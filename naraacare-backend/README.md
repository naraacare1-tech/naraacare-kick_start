# naraacare-backend

FastAPI API + taskiq background workers for NaraaCare. Python 3.13, dependencies managed with **uv** (lockfile committed).
Design docs: `docs/03-system-architecture.md`, `docs/04-api-specification.md`, `docs/07-security-architecture.md`, `docs/08-environment-and-config.md`.

## Layout

```
app/
  main.py                 app factory (uvicorn app.main:create_app --factory)
  api/v1/routers/         one router per domain: health, auth, me (profile/onboarding/targets/username/
                          entitlements), reference, privacy (consents); api/v1/deps.py = service lookup
  core/config.py          Settings: fails fast, never prints values
  core/logging.py         structlog JSON with PII redaction (keys, nested, exception messages dropped)
  core/exceptions.py      AppError + uniform error envelope; error_catalogue.py = every error code
  core/security/          validators.py (Safe* types), hashing.py (Argon2id passwords),
                          hashing.py (Argon2id), abuse.py (rejections -> events + penalty box),
                          tokens.py (EdDSA access/link tokens, refresh tokens), authz.py (current_user,
                          revocation deny-list, require_role, user_limit), passwords.py (policy + 10k
                          common passwords in data/), oauth.py (Google/Apple JWKS verification,
                          Apple code exchange)
  middleware/             request_id, access_log, security_headers, error_shield, docs_auth,
                          body_size_limit, rate_limit
  db/engine.py            async SQLAlchemy + asyncpg engines (PgBouncer-safe)
  repositories/base.py    Database / DbSession: stored function calls only (db_call), SQLSTATE mapping
  repositories/audit.py   async security-event writer
  repositories/           auth_repo, profile_repo, reference_repo, privacy_repo (one db_call per routine)
  domain/                 auth/service.py (sign-up, codes, sign-in, OAuth, sessions, passwords),
                          profile/service.py, nutrition|hydration/calculator.py (doc 06), targets.py,
                          common/calc_context.py (constants from ref.fn_calc_context), entitlements/,
                          reference.py (cached calc context + bootstrap)
  schemas/                request/response models (strict, Safe* strings only)
  integrations/email.py   fixed templates (app/templates/email), dev outbox / SMTP
  workers/broker.py       taskiq broker + scheduler
tests/  unit/ integration/ security/ (payload_sweep.py + payloads/xss.txt = shared payload list) contract/
semgrep/                  custom rules + fixtures (no bare str in schemas, no SQL string building, no print,
                          no body logging, no `= Query()` defaults that bypass Safe* validation)
tools/build_payloads.py   generates the shared payload list (copied to mobile + database repos)
tools/new_jwt_key.py      creates an Ed25519 key pair for access tokens
```

## Prerequisites

- [uv](https://docs.astral.sh/uv/) **0.13.6** (`pip install --user uv==0.13.6`); uv installs Python 3.13.17 itself.
- **PostgreSQL 18.6**, installed natively and migrated from `naraacare-database` (see that repo's README).
- **Redis 8.8** only for the background worker (taskiq queue). The API does not use Redis: rate limits, the logout deny-list and the lockout-notice dedupe live in memory (`app/core/memory_store.py`), so run the API as **one worker process** until Redis returns.
- No containers: everything runs as plain local processes.

## Setup

```bash
cp .env.example .env            # dummy values
uv sync                         # creates .venv with Python 3.13.17 + pinned deps
uv run pre-commit install       # gitleaks, ruff, mypy, payload-freshness hooks
```

## Run

```bash
# 1. PostgreSQL 18.6 running locally (Redis only if you run the worker); database migrated (naraacare-database README)
# 2. API (and, from the sessions that add them, the worker and scheduler)
uv run python -m uvicorn app.main:create_app --factory --reload --no-access-log --ws-max-size 8192
uv run python -m taskiq worker app.workers.broker:broker      # separate terminal
# No Redis on a dev machine: tools/dev_worker.py runs the report / export / support jobs in a
# loop instead (APP_ENV=dev only; DATABASE_URL in the environment = the app_worker login)
curl http://localhost:8000/api/v1/health/live       # {"status":"ok"}
```
Locally the API connects straight to PostgreSQL (no PgBouncer); the code is PgBouncer-safe for deployments that pool.
Dev email is written to `var/outbox/` as `.eml` files (open them in any mail client); dev file storage is `var/storage/`. Both folders are git-ignored.

## Test and quality gates (same as CI)

```bash
uv run python -m pytest # unit + integration + payload sweep, coverage gate 80 %
uv run coverage report --include="app/core/security/*" --fail-under=95
uv run ruff check . && uv run ruff format --check .
uv run mypy app tests tools                    # strict
uv run bandit -c pyproject.toml -r app
uv run pip-audit --strict
uvx --from semgrep==1.182.1 semgrep --test semgrep/
uvx --from semgrep==1.182.1 semgrep --error --config semgrep/general.yml app
uvx --from semgrep==1.182.1 semgrep --error --config semgrep/schemas.yml app/schemas
uv run python tools/build_payloads.py --check  # payload list up to date
```

Database integration tests (`-m db`) run against a migrated `naraacare-database` and are skipped
unless these are set:

```bash
export NARAACARE_TEST_DATABASE_URL=postgresql+asyncpg://app_rw:local-dev-only-app-rw@localhost:5432/naraacare_test
export NARAACARE_TEST_ADMIN_URL=postgresql://postgres:local-dev-only-postgres@localhost:5432/naraacare_test  # optional
```

They cover the full Session 05 flows (sign-up, codes, lockout, refresh rotation and reuse, password reset/change, Google/Apple with a local provider key, onboarding, targets, profile, username, consents). CI migrates a runner-installed PostgreSQL from `naraacare-database` at `DATABASE_REF` and runs them on every PR. After changing database routines, re-run `flyway migrate` on the test database first.

## Writing endpoints (Session 04/05 rules)

- Every string in a request model, query, path or header uses a `Safe*` type from
  `app/core/security/validators.py`, with the Annotated form: `q: Annotated[SafeSearchQuery, Query()]`.
  **Never `q: SafeSearchQuery = Query()`**: FastAPI then silently skips the validator (Semgrep blocks it,
  and the payload sweep would fail).
- Models: `ConfigDict(extra="forbid", strict=True)`; numbers with `Field(ge=, le=)`.
- Errors: `raise AppError(ErrorCode.X)`; never return exception text.
- Database: module-level `db_call("SELECT * FROM schema.fn_x(:a)")` / `db_call("CALL schema.pr_x(:a, NULL)")`
  constants, run inside `async with db.transaction(user_id=...)` (sets `app.user_id` / `app.request_id`).
- Rate limits: `dependencies=[Depends(rate_limit("auth_login"))]` (policies in `middleware/rate_limit.py`).
- New routes are swept automatically by `tests/security/test_payload_sweep.py` (OpenAPI-driven).
- Signed-in routes take `principal: CurrentUser` (never a user id from the client); per-user limits use
  `Depends(user_limit("writes"))` so they run after authentication. The sweep sends a valid token to
  secured routes automatically.
- Request models subclass a `strict=True` base; UUID, decimal and time fields use `JsonUUID`/
  `JsonDecimal`/`JsonTime` from `app/schemas/common.py`.
- Expected outcomes reported by procedures (`o_status`) are raised only after the transaction
  commits, so attempt counters persist; errors that must undo work are raised inside it.

## Shared payload list

`tests/security/payloads/base_vectors.txt` → `uv run python tools/build_payloads.py` → `xss.txt` (538 payloads, version `1.0.0`).
After changing it, copy the **identical** file to `naraacare-mobile/test/security/payloads/xss.txt` and `naraacare-database/tests/payloads/xss.txt`, and bump the version in all three repos' checks.

## Environment variables

Every key is in `.env.example` and validated by `app/core/config.py` (a test fails if the two drift). Required keys missing or invalid → the process exits listing **names only**.

| Key | Req | Secret | Description |
|---|---|---|---|
| `APP_ENV` | ✓ | | `dev` / `staging` / `prod`; enables guards (prod: docs off, no DEBUG, no CORS, master key required, SMTP email, TLS verify-full) |
| `APP_NAME`, `APP_VERSION`, `LOG_LEVEL` | | | service name, version, log level (DEBUG forbidden in prod) |
| `API_DOCS_ENABLED`, `API_DOCS_BASIC_AUTH` | | ✓ (auth) | OpenAPI docs toggle; basic auth required when enabled on staging |
| `ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS` | ✓ / | | Host header allow-list; CORS allow-list (empty in prod) |
| `DATABASE_URL`, `DATABASE_REPLICA_URL` | ✓ / | ✓ | `app_rw` (directly, or via PgBouncer when deployed); read replica |
| `DATABASE_SSL_MODE`, `DATABASE_SSL_ROOT_CERT` | ✓ / | | `verify-full` + the database provider's CA bundle outside dev |
| `DATABASE_POOL_SIZE`, `DATABASE_MAX_OVERFLOW` | | | pool tuning (statement timeouts are role settings in the database) |
| `REDIS_URL` | worker only | ✓ | taskiq queue for the background worker; the API ignores it |
| `JWT_ISSUER`, `JWT_AUDIENCE`, `JWT_ACTIVE_KID` | ✓ | | token claims / signing key id |
| `JWT_PRIVATE_KEY_PEM`, `JWT_PUBLIC_KEYS_JSON` | ✓ outside dev | ✓ | Ed25519 signing key + verification keys by `kid` (`tools/new_jwt_key.py`); empty in dev = ephemeral key, tokens die on restart |
| `ACCESS_TOKEN_TTL_SECONDS`, `REFRESH_TOKEN_TTL_DAYS`, `LINK_TOKEN_TTL_SECONDS` | | | 900 s / 60 days / 600 s |
| `ARGON2_*` | | | password hashing cost (OTP rules live in the auth service, lockout in the database) |
| `STORAGE_ROOT_DIR`, `STORAGE_CONTAINER_*` | ✓ (containers) | | object storage: `filesystem` in dev; the hosting provider's adapter is added in Session 17 |
| `EMAIL_BACKEND`, `EMAIL_OUTBOX_DIR`, `EMAIL_FROM_ADDRESS`, `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME` | ✓ (from) | | email: `outbox` (dev, files) or `smtp` (required outside dev; any provider) |
| `SMTP_PASSWORD` | | ✓ | SMTP credential |
| `SUPPORT_INBOX_ADDRESS` | ✓ | | support email |
| `GOOGLE_OAUTH_CLIENT_IDS`, `APPLE_BUNDLE_ID`, `APPLE_SERVICE_ID`, `APPLE_TEAM_ID`, `APPLE_SIWA_KEY_ID` | ✓ | | social login audiences |
| `GOOGLE_JWKS_URL`, `APPLE_JWKS_URL`, `APPLE_TOKEN_URL` | ✓ | | provider public keys + Apple code exchange (https only) |
| `APPLE_SIWA_PRIVATE_KEY_P8` | ✓ | ✓ | Sign in with Apple key |
| `GOOGLE_PLAY_PACKAGE_NAME`, `GOOGLE_RTDN_PUSH_AUDIENCE`, `GOOGLE_RTDN_SERVICE_ACCOUNT_EMAIL` | ✓ | | Play billing + RTDN verification |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | ✓ | ✓ | Play Developer API |
| `APP_STORE_ISSUER_ID`, `APP_STORE_KEY_ID`, `APP_STORE_ENVIRONMENT`, `APPLE_ROOT_CA_PATHS` | ✓ | | App Store Server API |
| `APP_STORE_PRIVATE_KEY_P8` | ✓ | ✓ | App Store Server API key |
| `GOOGLE_PLAY_API_BASE_URL`, `APP_STORE_API_BASE_URL`, `APP_STORE_SANDBOX_API_BASE_URL` | | | store APIs (https only, S11) |
| `PLAY_MANAGE_SUBSCRIPTIONS_URL`, `APP_STORE_MANAGE_SUBSCRIPTIONS_URL` | | | store "manage subscription" pages returned to the app (S11) |
| `FCM_SERVICE_ACCOUNT_JSON` | ✓ | ✓ | push (service-account key; a non-`service_account` value disables push in dev, refused elsewhere) |
| `FCM_API_BASE_URL`, `GOOGLE_OAUTH_TOKEN_URL` | | | FCM HTTP v1 and Google OAuth token endpoint (https only) |
| `RIN_ENABLED`, `RIN_MODEL` (gpt-5-mini), `RIN_EFFORT`, `RIN_MAX_OUTPUT_TOKENS` | | | Rin AI, drink estimates, report insights (doc 06 §8) |
| `RIN_MONTHLY_BUDGET_INR` | | | AI spend cap per user per local month across all AI features (owner: 10); Rin pauses until the next month |
| `AI_PRICE_INPUT_USD_PER_MTOK`, `AI_PRICE_CACHED_INPUT_USD_PER_MTOK`, `AI_PRICE_OUTPUT_USD_PER_MTOK`, `AI_USD_TO_INR` | | | OpenAI list prices and the exchange rate used to cost each call; update when they change |
| `OPENAI_API_KEY` | ✓ if Rin enabled | ✓ | OpenAI API (a `dummy...` value keeps Rin off: 503 "resting") |
| `OPEN_FOOD_FACTS_BASE_URL`, `OPEN_FOOD_FACTS_USER_AGENT` | | | barcode fallback |
| `REFERRAL_LINK_DOMAIN` | ✓ | | deep links |
| `MAX_BODY_BYTES`, `MAX_UPLOAD_BYTES` | | | limits |
| `WORKER_CONCURRENCY` | | | worker |

Empty values (`KEY=`) count as unset. Staging/prod values come from the hosting provider's secret manager (doc 08).

## Deployment

The API runs as a plain Python app, no container image: `uv sync --frozen --no-dev`, then
`uv run --no-sync uvicorn app.main:create_app --factory --no-server-header --no-access-log --ws-max-size 8192 --proxy-headers --forwarded-allow-ips <load balancer addresses>`
as an unprivileged user, as ONE process (no `--workers`): rate limits, the logout deny-list, WebSocket tickets and chat fan-out live in the process's memory (no Redis in the API). `--ws-max-size 8192` stops oversized WebSocket frames before they are read (the app also checks). `--no-access-log` because uvicorn's access log prints full URLs (AccessLogMiddleware logs route templates instead). The load balancer's health check uses `/api/v1/health/ready` (database). CI checks that the API starts this way (`startup` job).

## Trying the auth flow locally

With PostgreSQL migrated and the API running (`EMAIL_BACKEND=outbox`), sign up with `POST /api/v1/auth/signup`, then open the newest file in `var/outbox/` to read the 6-digit code and send it to `POST /api/v1/auth/otp/verify`. Codes never appear in logs. The OpenAPI page (`/api/v1/docs`, dev only) lists every endpoint. Google/Apple sign-in needs real client IDs; the tests use a locally generated provider key instead.

## Troubleshooting

- *"Invalid configuration: - X: Field required"* → add `X` to `.env` (see `.env.example`).
- *Signed out after restarting the API in dev* → expected with an empty `JWT_PRIVATE_KEY_PEM` (ephemeral key, log `jwt_ephemeral_key`); set a key from `tools/new_jwt_key.py` to keep sessions.
- *`apple_code_exchange_disabled` warning in dev* → no Sign in with Apple key configured; Apple sign-in still works, only the revocation token is not stored. Outside dev the API refuses to start without a valid key.
- *400 "Invalid host header"* → add the host you call to `ALLOWED_HOSTS`.
- *`/health/ready` reports `database` failing locally* → is PostgreSQL running and migrated (`naraacare-database` README)?
- *`/health/ready` returns 503* → the body says the database check failed; details are in the log line `readiness_*_failed`.
- *422 with `fields` but no reason* → by design: responses never echo input or say which rule matched. The log line `validation_rejected` lists `unsafe_fields`.

## Data storage

User data is stored in plain text so it can be read while debugging (owner decision, 2026-11-03):
email, OTP codes, names, medical condition codes, installation ids, IP addresses, push tokens,
purchase tokens, the Apple refresh token and circle chat messages. Only passwords (Argon2id), refresh
tokens and circle invite-link tokens (SHA-256; both are bearer secrets) are hashed. The database
domains still reject markup and scripting in every text column.

## Realtime (Session 12)

`POST /api/v1/realtime/ticket` returns a single-use ticket (30 s); the app opens
`wss://<host>/api/v1/ws?ticket=<ticket>` with it, so the access token never appears in a URL.
Client frames: `{"type":"ping"}` and `{"type":"typing","circle_id":"..."}` (8 KB max, 20 per 10 s).
Server events: `message.created`, `message.deleted`, `typing`, `circle.changed`, `notification`.
Social pushes are sent by the worker job `notify.send_social_pushes` (every minute) with fixed,
generic texts (no message text, names or health values).
