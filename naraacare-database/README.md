# naraacare-database

PostgreSQL 18.6 schema, stored functions/procedures, seed data and tests for NaraaCare.
The app never touches tables directly: the backend role `app_rw` only has `EXECUTE` on functions/procedures (doc 05 §7).

Design docs: `docs/05-database-design.md`, `docs/07-security-architecture.md`, session plans `sessions/session-02…03`.

## Layout

| Folder | Contents |
|---|---|
| `migrations/` | Flyway versioned scripts `V###__<verb>_<object>.sql` — **immutable once merged** |
| `functions/`, `procedures/`, `views/`, `triggers/`, `seed/` | Flyway repeatable scripts `R__<nn>_<schema>.<name>.sql` (`CREATE OR REPLACE`, re-applied on change). Prefix order: seed 10 → functions 20 → procedures 30 → views 40 → triggers 50 |
| `schemas/`, `roles/`, `tables/`, `indexes/` | Canonical current-state DDL per object (documentation + drift check) |
| `bootstrap/` | One-time bootstrap of any environment's database (creates `migration_owner`; idempotent) |
| `tests/` | pgTAP tests; `tests/payloads/xss.txt` = shared script/markup payload list, `xss_payloads.psql` = generated fixture |
| `tools/canonical_order.txt` | Dependency order of the canonical files and which baseline migration each belongs to |
| `tools/` | `local_setup.sh`, `install_pgtap.sh`, `run_pgtap.sh`, `drift_check.sh` (+ shared `pg_env.sh`), `check_payload_version.sh`, `build_baseline.py`, `build_payload_fixture.py`, `check_invisible_chars.py`, `function_catalog.sql` |
| `functions/README.md` | Generated catalogue of every function/procedure: owner, who may call it, purpose |

## Prerequisites

Everything runs natively, no containers:

- **PostgreSQL 18.6** server and client tools (`psql`, `pg_dump`, `pg_config`) on `PATH`. Linux: the PGDG apt/yum packages; Windows/macOS: the EDB installer or Postgres.app. Set the `postgres` superuser password to the one in `.env`.
- **Flyway CLI 13.11.1** on `PATH` (or `FLYWAY=/path/to/flyway`; `flyway.cmd` on Windows).
- **pgTAP 1.3.4**: `bash tools/install_pgtap.sh` (downloads from PGXN, sha256-verified, local/CI only). `pg_prove` is optional; without it `run_pgtap.sh` runs each test file with `psql`.
- Git, bash (Git Bash on Windows). Optional: `pip install pre-commit==4.7.0 sqlfluff==4.4.0`.

## Setup and run

```bash
cp .env.example .env                  # dummy local values
pre-commit install                    # gitleaks + sqlfluff + hygiene hooks
bash tools/install_pgtap.sh           # once per PostgreSQL install
bash tools/local_setup.sh             # creates the dev database, migration_owner, applies migrations
```

## Test

```bash
bash tools/run_pgtap.sh                       # recreate test DB, migrate from empty, run pgTAP (905 assertions)
bash tools/drift_check.sh                     # migrations vs canonical DDL must match
sqlfluff lint migrations schemas roles tables indexes seed tests
python tools/build_baseline.py --check        # manifest complete, every group has its migration
python tools/build_payload_fixture.py --check # fixture matches xss.txt
python tools/check_invisible_chars.py migrations schemas roles tables indexes seed tests
```

| Test file | Covers |
|---|---|
| `000_smoke` | extensions, PostgreSQL 18, V001 recorded |
| `010_schemas_roles` | schemas, role attributes, **app roles have zero table privileges**, api_definer DML, nothing PUBLIC-executable |
| `020_constraints` | every range/enum/domain boundary (age 17/18/100/101, 120 cm, 15–40 °C, 1–3000 mL, −100 swipe rule, 16 h sleep, no overlapping sleep, OTP attempts…) |
| `030_indexes` | every index documents the query it serves; every FK (outside ref lookups) has an index |
| `040_rls` | RLS on every user-owned table; user A cannot see, insert or update user B's rows |
| `050_seed` | reference data equals doc 06 (multipliers, factors, goals, BMI blocks, portions, tier matrix) |
| `060_security_payloads` | all 529 storable payloads rejected by `common.safe_text`; no bare text columns; every free-text column has a length limit |
| `070_partitions` | DEFAULT + current..+3 month partitions; rows route to the right month |
| `100_common` | actor helpers (`42501` on mismatch), `fn_validate_text` rejects all payloads, user-local dates, `updated_at` triggers everywhere |
| `110_audit` | audit rows with redacted ciphertext/hashes, only changed columns, actor + request id; security-event details cannot carry text; consent history append-only |
| `120_auth_procs` | OTP (3 attempts, expiry, single use, 30 s cooldown, 5/h), lockout backoff 1/5/15/60 min, refresh rotation + reuse → family revoked, password history (5), social sign-in never links silently |
| `130_app_procs` | onboarding order and consents, today's snapshot replaced / past kept, username 90-day rule and uniqueness across RLS, settings, entitlement (store > grant > STANDARD), bootstrap ETag, payloads through every text parameter |
| `140_ops` | partitions for a mocked date, idempotent, DEFAULT-not-empty alert, retention drops only expired partitions, batched auth purge |
| `150_grants_security_definer` | every routine pins `search_path`; owners; PUBLIC executes nothing; `app_rw` only reaches definer entry points; no dynamic SQL outside `ops` |
| `160_auth_integration` | routines added for the S05 API: OTP resend lookup, password rehash (compare-and-swap), Apple refresh-token storage (actor only), calc context, current policies, current consents (latest per purpose, actor only) |

## Functions and procedures

- One routine per file in `functions/` (`R__2x_…`) or `procedures/` (`R__3x_…`), `CREATE OR REPLACE`, re-applied by Flyway when the file changes.
- API routines start with `SET LOCAL ROLE api_definer;` so they are **owned by `api_definer`** (subject to RLS), are `SECURITY DEFINER` with `SET search_path = pg_catalog, pg_temp`, `REVOKE ALL … FROM PUBLIC` and an explicit `GRANT EXECUTE … TO app_rw` (and `app_worker`/`app_readonly` where needed).
- Every routine taking `p_user_id` calls `common.fn_assert_actor(p_user_id)` first. The API sets `app.user_id` (and `app.request_id`) per transaction with `set_config(…, true)`.
- Errors: `22023` invalid input, `42501` not the actor (API → 404), `P0001` with the app error code in `DETAIL` (e.g. `USERNAME_TAKEN`). Outcomes that must persist (OTP attempts, lockouts, token reuse) are **returned in `o_status`**, never raised, because raising would roll them back.
- Owner-run exceptions (table owner `migration_owner`, exempt from RLS): `ops.*`, `app.fn_username_available` (returns only a boolean) and the audit trigger. `tests/150` keeps this list closed.
- After changing routines regenerate the catalogue: `psql -X -At -d naraacare_test -f tools/function_catalog.sql > functions/README.md` (CI fails if it is stale).

## Changing the schema

1. Edit or add the canonical file(s) in `schemas/ roles/ tables/ indexes/` (and list new ones in `tools/canonical_order.txt`).
2. Write a new migration `migrations/V0NN__<verb>_<object>.sql` with the same change. **Never edit a merged migration.**
3. Run `tools/run_pgtap.sh` and `tools/drift_check.sh`: the drift check proves 1 and 2 agree.

Seeds (`seed/R__*.sql`) are repeatable and idempotent; calculation constants of a released `calc_version` are immutable (the seed raises if one changes; add a new version instead).
**Write regexes with escapes only** (e.g. `​`), never literal invisible characters; CI rejects them.

To reset the dev database locally: `psql -U postgres -c 'DROP DATABASE naraacare WITH (FORCE)'`, then `bash tools/local_setup.sh`.

## Environment variables

| Key | Required | Secret | Example | Description |
|---|---|---|---|---|
| `PGHOST` / `PGPORT` / `PGDATABASE` | ✓ | | `localhost` / `5432` / `naraacare` | target database |
| `FLYWAY_URL` | ✓ | | `jdbc:postgresql://localhost:5432/naraacare?sslmode=disable` | `sslmode=verify-full` outside dev |
| `FLYWAY_USER` / `FLYWAY_PASSWORD` | ✓ | ✓ | `migration_owner` / dummy | migration role |
| `FLYWAY_LOCATIONS` | ✓ | | `filesystem:migrations,…` | script folders |
| `FLYWAY_PLACEHOLDERS_APP_RW_PASSWORD` | ✓ (first deploy) | ✓ | dummy | `app_rw` role password (S02) |
| `FLYWAY_PLACEHOLDERS_APP_WORKER_PASSWORD` / `_APP_READONLY_PASSWORD` / `_REPORTING_PASSWORD` | ✓ | ✓ | dummy | other app role passwords |
| `FLYWAY_PLACEHOLDERS_SEED_SAMPLE_FOODS` | ✓ | | `true` (dev/staging) | loads approximate development foods; **must be `false` in prod** |
| `FLYWAY_VALIDATE_MIGRATION_NAMING` | | | `true` | reject badly named scripts |
| `FLYWAY_CLEAN_DISABLED` | ✓ | | `true` | `flyway clean` is never allowed outside a throwaway local DB |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | ✓ (local/CI only) | | `postgres` / dummy | local superuser for bootstrap, test databases and pgTAP |
| `PGTAP_DATABASE` | | | `naraacare_test` | test database name |

Staging/prod: the deploy job reads secrets from the hosting provider's secret manager; no `.env` file exists there.

## Pinned versions

PostgreSQL `18.6` locally (CI: the current PostgreSQL 18 minor from the PGDG apt repository; PGDG keeps only the latest minor, and minors never change behaviour the tests depend on), Flyway `13.11.1` (CLI tarball, sha256-verified in CI), pgTAP `1.3.4` (PGXN, sha256-verified), sqlfluff `4.4.0`, gitleaks `8.30.1`.

## Rules (summary of doc 09 §6)

- Every text column: `common.safe_text` domain + `char_length` CHECK (from S02).
- Functions `fn_` (reads, `STABLE`), procedures `pr_` (writes). `SECURITY DEFINER` only with `SET search_path = pg_catalog, pg_temp`.
- No dynamic SQL except `ops.*` using `format('%I', …)`.
- Every index file has `COMMENT ON INDEX … IS 'serves: …'`.

## Troubleshooting

- *`role "migration_owner" does not exist`*: run `bash tools/local_setup.sh` (it runs `bootstrap/bootstrap.sql`).
- *`extension "pgtap" is not available`*: run `bash tools/install_pgtap.sh` against the same PostgreSQL install (`pg_config` decides where it goes).
- *CRLF errors in scripts on Windows*: `.gitattributes` forces LF; run `git add --renormalize .` after cloning with old settings.
