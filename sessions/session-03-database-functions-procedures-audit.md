# Session 03 — Database: Stored Procedures, Functions, Triggers, Audit, Partition Maintenance

## Goal and scope
Build the generic DB machinery every later feature relies on: audit/`updated_at` triggers, security-event writer, partition maintenance, retention, the session-context helpers, entitlement function, and the **auth/profile** functions and procedures needed by S05.

**In:** `common.*` trigger functions; `audit.*` writers; `ops.*` maintenance; `app`/`auth` read functions and write procedures; `billing.fn_current_entitlement`; error-code conventions; grants.
**Out:** nutrition/hydration/sleep/social/AI procedures (built in their feature sessions using the same patterns).

## Prerequisites
S02 complete.

## Files to create (naraacare-database)
```
functions/R__20_common.fn_current_user_id.sql        # current_setting('app.user_id', true)::uuid, raises 42501 if null
functions/R__20_common.fn_assert_actor.sql           # assert p_user_id = app.user_id
functions/R__20_common.fn_validate_text.sql          # casts to common.safe_text + length; raises 22023
functions/R__21_common.trg_fn_set_updated_at.sql
functions/R__21_audit.trg_fn_audit_row.sql           # writes audit.change_log; redacts *_ct, password_hash, token_hash
functions/R__22_billing.fn_current_entitlement.sql   # tier, source, expires_at, features jsonb, limits jsonb
functions/R__22_ref.fn_bootstrap.sql                 # reference payload (one JSON doc, ETag hash)
functions/R__23_auth.fn_find_account_by_email_bidx.sql
functions/R__23_auth.fn_find_identity.sql
functions/R__23_auth.fn_refresh_token_lookup.sql
functions/R__23_auth.fn_login_failures_recent.sql
functions/R__24_app.fn_get_profile.sql               # profile + onboarding state + counts
functions/R__24_app.fn_username_available.sql
functions/R__24_app.fn_latest_target_snapshot.sql
procedures/R__30_audit.pr_log_security_event.sql
procedures/R__30_auth.pr_create_account.sql          # inserts user_account (pending_verification) + otp_challenge
procedures/R__30_auth.pr_create_otp_challenge.sql    # resend rules: cooldown, send_count ≤ 5/h
procedures/R__30_auth.pr_verify_otp.sql              # attempts++, expiry, single use; activates account
procedures/R__30_auth.pr_record_login_attempt.sql    # lockout counters + locked_until (backoff 1/5/15/60 min)
procedures/R__30_auth.pr_issue_refresh_token.sql
procedures/R__30_auth.pr_rotate_refresh_token.sql    # detects reuse → revokes family, logs security event, returns reuse flag
procedures/R__30_auth.pr_revoke_tokens.sql           # family | all for user (reason)
functions/R__23_auth.fn_password_history.sql         # last 5 hashes (for API-side Argon2 comparison, see note)
procedures/R__30_auth.pr_set_password.sql            # stores new hash, appends history (keeps 5), revokes sessions
procedures/R__30_auth.pr_link_identity.sql
procedures/R__31_app.pr_save_onboarding_step.sql
procedures/R__31_app.pr_complete_onboarding.sql      # stores target snapshot computed by API, consents
procedures/R__31_app.pr_update_profile.sql           # today's snapshot replace; past untouched
procedures/R__31_app.pr_set_username.sql             # uniqueness + 90-day rule
procedures/R__31_app.pr_update_settings.sql
procedures/R__31_privacy.pr_record_consent.sql       # append-only
procedures/R__32_ops.pr_ensure_partitions.sql        # format('%I') DDL, premake 3, DEFAULT partition check
procedures/R__32_ops.pr_apply_retention.sql
procedures/R__32_ops.pr_purge_auth_artifacts.sql
triggers/R__50_triggers_updated_at.sql               # attach to all +STD tables
triggers/R__50_triggers_audit.sql                    # attach to sensitive tables (doc 07 SEC-4.7)
triggers/R__50_triggers_consent_append_only.sql      # raise on UPDATE/DELETE
migrations/V014__grant_execute.sql                   # GRANT EXECUTE on fn_/pr_ to app_rw/app_worker; REVOKE FROM PUBLIC; ALTER … OWNER TO api_definer
tests/100_common.sql tests/110_audit.sql tests/120_auth_procs.sql tests/130_app_procs.sql tests/140_ops.sql tests/150_grants_security_definer.sql
```
Note on password history: hashes are Argon2id (salted), so comparison happens in the API: `fn_password_history(user)` returns the last 5 hashes, the API verifies the candidate against each, then calls `pr_set_password`.

## Step-by-step tasks
1. Define the function template (every function/procedure):
   ```sql
   CREATE OR REPLACE PROCEDURE auth.pr_verify_otp(p_challenge_id uuid, p_code_ok boolean, INOUT o_user_id uuid DEFAULT NULL, INOUT o_status text DEFAULT NULL)
   LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, pg_temp AS $$ … $$;
   ```
   (OTP hash verification is done in Python with Argon2; the procedure enforces attempts/expiry/single-use atomically with `SELECT … FOR UPDATE`.)
2. Error-code convention: `22023` invalid input, `42501` not owner/not found-for-actor, `P0001` with `DETAIL='<APP_CODE>'` for business errors (e.g. `OTP_EXPIRED`, `USERNAME_CHANGE_TOO_SOON`, `DAILY_LIMIT_REACHED`), `40001` serialization → API retries once.
3. Audit trigger: captures `app.user_id`, `app.request_id` (set by API per transaction), changed columns, redacted values.
4. `ops.pr_ensure_partitions`: for each `ops.partition_config` row create `<table>_yYYYYmMM` partitions for the current + 3 months; alert (RAISE WARNING + row in `audit.security_event` type `ops_alert`) if DEFAULT partitions contain rows.
5. Grants + ownership migration; verify no function is executable by PUBLIC.
6. Document each function signature in `functions/README.md` (generated table).

## DB objects created
Functions/procedures/triggers listed above; `V014` grants.

## API endpoints
None (consumed by S05).

## Screens
None.

## Security checks
SEC-4.1 (no dynamic SQL except `ops` with `format('%I')`), SEC-4.3 (`SECURITY DEFINER` + fixed `search_path`, owner `api_definer`), SEC-4.4 (actor assertion in every function taking `p_user_id`), SEC-4.7 (audit triggers with redaction), SEC-1.3/1.6 enforced atomically in procedures, SEC-7.1 (append-only consent).

## Input-validation checklist
- [ ] Every text parameter goes through `common.fn_validate_text(p, max)` or a domain cast; invalid → `22023`.
- [ ] Username parameters cast to `common.username`.
- [ ] Payload test calls each text-accepting procedure with every payload → exception.

## Tests to write (pgTAP)
OTP: 3 wrong → dead challenge; expired → `OTP_EXPIRED`; consumed → cannot reuse; resend before 30 s → error; 6th send in an hour → error. Refresh: rotate returns new token; reusing old → family revoked + security event row. Lockout: 5 failures → `locked_until` set with backoff. Username: duplicate (case-insensitive) rejected; second change within 90 days rejected. Profile update writes today's snapshot only. Audit rows created with redaction (no ciphertext/hash in `old_values`). Partitions: run for a mocked date → new partitions created; idempotent. Grants: `has_function_privilege('app_rw', …)` true for API functions, false for `ops.*`; `PUBLIC` false everywhere; every SECURITY DEFINER function has `proconfig` containing `search_path=pg_catalog, pg_temp`. Actor mismatch → `42501`.

## Acceptance criteria / Definition of done
- [ ] All functions/procedures compile via Flyway `R__` and are owned by `api_definer`.
- [ ] pgTAP suite green; payload tests green.
- [ ] A query in tests proves no SECURITY DEFINER function lacks a fixed search_path.
- [ ] Audit log never stores ciphertext, password hashes, token hashes or OTP hashes.
- [ ] `ops.pr_ensure_partitions` creates future partitions and is idempotent.

## Estimated effort
4–5 developer-days.

## Implementation status (2026-10-27)

Verified on local PostgreSQL 18.6 + Flyway 13.11.1 + pgTAP 1.3.4 (native binaries; the same scripts CI runs).

| Acceptance criterion | Status |
|---|---|
| Routines compile via Flyway `R__`; API routines owned by `api_definer` | ✅ 14 versioned + 49 repeatable scripts (63 from empty); 29 routines owned by `api_definer`, 13 by `migration_owner` (common helpers, trigger functions, owner-run allow-list) |
| pgTAP suite green; payload tests green | ✅ 876 assertions in 14 files (200 new across 100–150); all 529 payloads rejected by `fn_validate_text`, security-event details and every text-typed procedure parameter |
| No SECURITY DEFINER routine without a fixed search_path | ✅ `tests/150`; in fact every routine pins `search_path = pg_catalog, pg_temp` |
| Audit log never stores ciphertext or hashes | ✅ `tests/110` (redaction + a scan of every audit row) |
| `ops.pr_ensure_partitions` creates future partitions and is idempotent | ✅ `tests/140` with a mocked date (36 created, 0 on re-run) |
| Drift check, sqlfluff, baseline/fixture/invisible-character checks | ✅ no drift (4,939 schema lines); lint clean |
| Re-run / re-apply | ✅ second `flyway migrate` is a no-op; every `R__` script re-applies cleanly over itself |

Built: 42 routines (catalogue in `naraacare-database/functions/README.md`, generated by `tools/function_catalog.sql`), 3 trigger scripts, `V014__grant_function_privileges`, retention seed `R__15`.

Added beyond the plan (needed by S05): `auth.fn_get_otp_challenge`, `auth.pr_resend_otp`, `auth.pr_create_oauth_account`, `common.fn_local_date`, internal `app.pr_upsert_target_snapshot`, `privacy.trg_fn_append_only`.

Defects found during the session:
- **Ownership hand-over failed**: `migration_owner` can SET ROLE to `api_definer` but does not inherit its rights, so `ALTER … OWNER TO` followed by `GRANT` was refused (and a later deploy could not have replaced the function). Fixed by creating API routines with `SET LOCAL ROLE api_definer`; the drift check now applies files in one transaction each, like Flyway.
- **`app.fn_get_profile` returned `text` where the signature declares a domain**: GET /me would have failed for every user. Caught by `tests/130`, fixed with explicit casts.

Deviations (docs updated): no `V014` per-function grants (grants live in each `R__` file, because versioned scripts run before repeatables); V014 instead holds schema `CREATE` for `api_definer` and the audit/consent hardening; owner-run allow-list (doc 05 §7); outcomes that must persist are returned in `o_status`, not raised (doc 04 §1.1); partition names keep the S02 form `<table>_pYYYY_MM`. New **OQ-60** (refresh-token reuse grace window).
