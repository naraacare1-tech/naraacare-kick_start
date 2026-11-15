# Session 04 — Backend: Core Config, Logging, Error Handling, Security Middleware, Safe* Validators

## Goal and scope
Build the backend chassis every endpoint uses: settings, structured logging with PII redaction, error envelope, middleware stack, rate limiting, DB access layer (session context + function calls), field encryption, and the **Safe\* input validators** with the full payload test harness.

**In:** `app/core/*`, `app/middleware/*`, `app/repositories/base.py`, `app/core/security/{validators,crypto,hashing}.py`, error catalogue, OpenAPI config, payload sweep framework, Semgrep rules active.
**Out:** auth endpoints (S05), business endpoints.

## Prerequisites
S01; S03 (for `common.fn_*` and error codes).

## Files to create (naraacare-backend)
```
app/core/config.py                    # Settings (doc 08 §2) with prod guards
app/core/logging.py                   # structlog JSON; processors: request_id, redact_keys, drop_bodies, truncate
app/core/exceptions.py                # AppError(code, http_status, message_key); handlers for RequestValidationError → 422 generic; HTTPException; Exception → 500
app/core/error_catalogue.py           # all codes from doc 04 §1.1
app/core/security/validators.py       # Safe* types (doc 04 §1.2) + normalise() + REJECT_PATTERNS (doc 07 §4.2)
app/core/security/hashing.py          # Argon2id hasher (password + OTP profiles), needs_rehash
app/core/security/crypto.py           # AES-256-GCM envelope (data keys wrapped by a master key from the secret manager; local key in dev), blind_index()
app/core/security/request_context.py  # contextvars: request_id, user_id
app/middleware/request_id.py          # accept UUID X-Request-ID or generate; echo header
app/middleware/security_headers.py    # doc 07 §5 header set; remove Server
app/middleware/body_size_limit.py     # 1 MB default; route overrides
app/middleware/rate_limit.py          # Redis sliding window; per user/IP; route policies; Retry-After; validation-reject penalty box
app/middleware/access_log.py          # method, route template, status, duration, user_id, request_id (no query strings with PII)
app/db/engine.py                      # SQLAlchemy 2.1 async engine (asyncpg), PgBouncer-safe settings, primary + replica
app/repositories/base.py              # async with db.transaction(user_id, request_id): set_config('app.user_id'), set_config('app.request_id'); call_fn(), call_proc(); maps SQLSTATE → AppError
app/main.py                           # middleware order (doc 03 §4), routers, docs gating, lifespan (validate config, unwrap the DEKs)
semgrep/rules.yml                     # activate: no-bare-str-in-schemas, no-sql-string-building, no-print, no-logging-of-request-body
tests/unit/core/test_validators.py    # table-driven: valid samples (Hindi/Marathi/Tamil names, O'Brien, Jean-Luc) + all payloads
tests/unit/core/test_crypto.py tests/unit/core/test_hashing.py tests/unit/core/test_logging_redaction.py
tests/integration/test_middleware.py  # headers, request id, body limit, rate limit, error envelope
tests/security/payload_sweep.py       # framework: load OpenAPI, enumerate string fields (body/query/path/header), send payloads, assert 422 + log check
tests/security/payloads/xss.txt       # v1.0.0
```

## Step-by-step tasks
1. `Settings` with all keys known now; prod guards; `SecretStr` for secrets.
2. Logging: JSON lines; redaction processor drops keys matching doc 07 SEC-7.4 regex; never log bodies or headers except `X-Request-ID`, `User-Agent` (truncated).
3. Validators:
   - `normalise(raw, multiline=False)`: reject R5 on raw → NFKC → reject R6/R7/R8 on raw (except types that allow `%`/`&` literally; those still reject entity/encoding *patterns*) → iterative decode (≤ 3) for inspection → R1–R4, R9 on normalised + decoded + whitespace-stripped forms → allow-list regex (`regex` module with `\p{L}\p{M}\p{N}` support) → length.
   - Each `Safe*` = `Annotated[str, BeforeValidator(type_check), AfterValidator(rule), Field(max_length=…)]` so OpenAPI shows maxLength.
   - Rejection raises `PydanticCustomError("unsafe_input", "Input contains characters that are not allowed")`.
4. Exception handlers: `RequestValidationError` → 422 envelope with field **names** only; log `security_event(validation_rejected)` when the error type is `unsafe_input`, via `audit.pr_log_security_event` (async, fire-and-forget queue) without the value.
5. Rate limiter: Redis Lua sliding window; policies per route (decorator `@rate_limit("auth_login")`); penalty box after 10 unsafe rejections/10 min.
6. DB layer: `transaction(user_id)` sets `app.user_id` / `app.request_id` with `set_config(..., true)`; SQLSTATE mapping (doc 09 §6); retry once on `40001`.
7. Crypto: `encrypt(plaintext, aad=table.column)` / `decrypt`; AAD binds ciphertext to its column (prevents swapping); blind index HMAC-SHA256.
8. Wire middleware order and docs gating; `/health/ready` (DB `SELECT 1` via a `ops.fn_ping()` function + Redis ping).
9. Payload sweep framework running against a dummy echo router in tests (real endpoints are added to the sweep automatically as they appear).

## DB objects
Uses `audit.pr_log_security_event`, adds `ops.fn_ping()` (R__ function) if not present.

## API endpoints
`GET /health/ready` (internal).

## Screens
None.

## Security checks
SEC-2.4 (authoritative validation), SEC-3.1/3.2/3.3/3.4 (validation, rate limits, headers/CORS, size limits), SEC-3.5 uniform errors, SEC-3.6 request ID, SEC-4.1 (only function calls), SEC-4.5 field encryption, SEC-7.4 redaction, SEC-8.3 Semgrep rules enforced.

## Input-validation checklist
- [ ] All `Safe*` types from doc 04 §1.2 implemented with max length and allow-list.
- [ ] Normalisation covers NFKC, URL decode, entity decode, Unicode escapes, mixed case, zero-width/bidi chars.
- [ ] Rejected input never echoed in responses or logs (test captures logs).
- [ ] Repeated rejections tighten rate limits and raise an alert event.
- [ ] Semgrep fails the build on a bare `str` field in `app/schemas/`.

## Tests to write
Validator unit tests (≥ 300 payloads rejected; ≥ 100 legitimate inputs accepted incl. Indic scripts, apostrophes, hyphens, emoji only in chat); crypto round-trip + tamper detection + AAD mismatch; Argon2 parameters; logging redaction; middleware integration (security headers present on 200/4xx/5xx, body > 1 MB → 413, rate limit → 429 with Retry-After, error envelope shape, no stack traces in 500).

## Acceptance criteria / Definition of done
- [ ] Every payload in `xss.txt` is rejected by every applicable Safe* type; legitimate multilingual samples pass.
- [ ] 500 responses contain only `INTERNAL_ERROR` + request id.
- [ ] Security headers match doc 07 §5 exactly.
- [ ] Logs contain no bodies/PII (automated check).
- [ ] App refuses to start in `prod` with docs enabled or a local encryption key.
- [ ] Coverage ≥ 95 % for `app/core/security/`.

## Estimated effort
4 developer-days.

## Implementation status (2026-10-29)

Verified locally: Python 3.13.17 via uv, against the migrated PostgreSQL 18.6 from `naraacare-database` (native binaries).

| Acceptance criterion | Status |
|---|---|
| Every payload rejected by every applicable Safe* type; multilingual input passes | ✅ all 538 payloads rejected by all 27 type aliases; 140 legitimate samples accepted (10 Indian languages in 9 scripts, plus Urdu, O'Brien, Jean-Luc, smart apostrophes, emoji in chat) |
| Payload sweep over the API | ✅ OpenAPI-driven: 4,228 hostile requests across body/query/path/header fields, all 422, no payload in responses or logs |
| 500 responses contain only `INTERNAL_ERROR` + request id | ✅ `ErrorShieldMiddleware`; exception messages are not logged either |
| Security headers match doc 07 §5 | ✅ on 200/404/409/422/429/500 (Permissions-Policy corrected, see below) |
| Logs contain no bodies/PII (automated check) | ✅ redaction tests + the sweep scans captured logs |
| Refuses to start in prod with docs enabled or a local key | ✅ settings guards (tests) |
| Coverage ≥ 95 % for `app/core/security/` | ✅ 98 % (CI gate added); whole app 95.8 % |
| ruff, mypy --strict, bandit, Semgrep (5 custom rules + self-tests), pip-audit | ✅ all clean |

Tests: 384 (9 database integration tests run as the real `app_rw` role when `NARAACARE_TEST_DATABASE_URL` is set, otherwise skipped). Database side: `ops.fn_ping()` added for the readiness probe; pgTAP 878 assertions, no drift, sqlfluff clean.

Defects and risks found during the session:
- **FastAPI parameter footgun**: `q: SafeSearchQuery = Query()` silently skips the Safe* validator (`Annotated[SafeSearchQuery, Query()]` works). New Semgrep rule `no-param-default-validation-bypass`, a test pinning the behaviour, and the sweep would catch any route written that way.
- **URLs in third-party logs**: the HTTP client library logs full URLs at INFO (outbound calls to Google/Apple/Anthropic would leak tokens and ids). Those loggers are capped at WARNING; uvicorn's access log is disabled (`--no-access-log` in the run command).
- **Chunked bodies over 1 MB returned 400, not 413**: FastAPI wraps errors raised while it reads the body. The limiter now reads and counts the body itself.
- **Procedures without output parameters** crashed the result reader (`DbSession.execute` added); Redis replies are bytes (fixed in the limiter).
- **Escapes turned into invisible characters by the editing tool** (again, as in Session 01): found in the new tests and in Session 01's `base_vectors.txt`. Fixed; `tests/security/test_source_hygiene.py` now fails on any invisible/bidi character in backend sources. The generated payload list is unchanged (version 1.0.0).

Decisions (docs 03, 04, 07, 08 updated):
- Parameterised Safe* types are one alias per size (`SafeShortText40`, `SafeOpaqueToken256` …), so mypy and Semgrep see a named type everywhere.
- Each Safe* field publishes `x-safe-kind` in OpenAPI; a test fails on any bare string field.
- Passwords get the reject patterns (no allow-list) after NFKC; `SafeNewPassword` adds an upper-case letter and a digit.
- Rate limiter: Redis sliding-window counter, failing open if Redis is down (lockouts stay in the DB).
- Field keys: DEKs wrapped by a master key in `FIELD_ENCRYPTION_DEKS_JSON` plus `FIELD_ENCRYPTION_ACTIVE_KEY_ID` (new settings), made with `tools/new_dek.py`. Changed 2026-10-29 (no AWS): the master key is `FIELD_ENCRYPTION_MASTER_KEY_B64` in the secret manager, the wrap is AES-256-GCM with the key id authenticated; `boto3` removed.
- `Permissions-Policy: ()` from doc 07 is not valid syntax; replaced by an explicit list.
- New pins: `regex`, `email-validator`, `tzdata` (dev: `fakeredis`, `pytest-asyncio`, `types-regex`).
- New **OQ-61**: chat emoji with joiners pass the API but the DB domain rejects them (resolve in S12, recommended: chat stored as ciphertext).

Not done here: CI for the backend does not yet start PostgreSQL, so the 9 DB tests are skipped there until the backend CI checks out `naraacare-database` at a pinned tag and migrates a runner-installed PostgreSQL (needs the GitHub repos).
