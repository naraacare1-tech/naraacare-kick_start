# Session 02 — Database: Schemas, Roles, Core Tables, CHECK Constraints, Indexes, Seed Data

## Goal and scope
Create all schemas, domains, roles/grants and the tables needed by sessions 05–11 (identity, profile, reference, tracking, billing basics, audit, ops), with every CHECK constraint, index (with comments), partitioning, RLS enablement and reference seed data from doc 06.

**In:** schemas `common, auth, app, ref, activity, nutrition, hydration, sleep, billing, notify, privacy, audit, ops`; tables of doc 05 §5.1–5.5, 5.8 (core), 5.9 (`notify.device`, `notify.notification_preference`, `privacy.consent_record`), 5.10; seed data; partitions for the next 3 months.
**Out:** functions/procedures/triggers (S03); `social`, `ai`, `support`, `report` tables (created in S12/S13/S14).

## Prerequisites
S01 complete. OQ-12/13/14 defaults accepted for seeding (values are data — can change later via new `calc_version`).

## Files to create (naraacare-database)
```
migrations/V002__schemas_and_domains.sql       # schemas + common domains (doc 05 §4); REVOKE ALL ON SCHEMA public FROM PUBLIC
migrations/V003__roles_and_grants.sql          # migration_owner, api_definer (NOLOGIN), app_rw, app_worker, app_readonly, reporting; default privileges
migrations/V004__auth_tables.sql               # user_account, identity_link, otp_challenge, refresh_token, password_history, login_attempt
migrations/V005__ref_tables.sql                # all ref.* tables (doc 05 §5.3)
migrations/V006__app_tables.sql                # user_profile, health_target_snapshot, user_activity_day, user_streak
migrations/V007__nutrition_tables.sql          # food_item, food_alias, food_unit_override, barcode_product, meal (P), meal_item (P), daily_summary (P), saved_meal(+item) (food_request dropped later by V015, OQ-63)
migrations/V008__activity_hydration_sleep.sql  # activity.workout (P), hydration.intake (P), custom_drink, temperature_log, daily_summary (P), sleep.entry, night_waking, daily_summary
migrations/V009__billing_core.sql              # store_product, subscription, store_transaction, store_notification, entitlement_grant, referral_code, referral, referral_reward
migrations/V010__notify_privacy_core.sql       # notify.device, notification_preference, reminder, notification (P); privacy.consent_record, export_request, deletion_request, retention_policy
migrations/V011__audit_ops.sql                 # audit.change_log (P), security_event (P), ops.partition_config
migrations/V012__initial_partitions.sql        # DEFAULT + current month + 3 ahead for each partitioned table (static DDL; S03 automates)
migrations/V013__enable_rls.sql                # ENABLE + FORCE RLS and own_rows policies on user-owned tables
schemas/*.sql  tables/<schema>.<table>.sql  indexes/<schema>.<table>.sql  roles/*.sql   # canonical current-state copies
seed/R__10_seed_ref_calc.sql          # calc_version 2026.1 + calc_constant (all hydration/nutrition constants, source + is_product_choice)
seed/R__11_seed_ref_profile.sql       # activity_level, hydration_activity, body_type, weight_goal, bmi_category, sleep_goal_by_age, avatar (6), medical_condition (placeholder list, OQ-33)
seed/R__12_seed_ref_tracking.sql      # drink_type (8), workout_type (6), nutrient (17), unit, food_category, food_category_unit (doc 06 §2.10)
seed/R__13_seed_ref_billing.sql       # subscription_tier, feature_entitlement (doc 04 §3), store_product (4 ids), policy_document (placeholder versions), feature_flag, wallpaper
seed/R__14_seed_food_sample.sql       # ~50 sample foods incl. Roti, Moong Dal (Cooked/Tadka), Rice, Curd, Aloo Sabzi, Apple, Moong Dal Chilla, Milk, Tea + Hinglish aliases (dev/staging only via placeholder ${seed_sample_foods})
tests/010_schemas_roles.sql  tests/020_constraints.sql  tests/030_indexes.sql  tests/040_rls.sql  tests/050_seed.sql  tests/060_security_payloads.sql
```

## Step-by-step tasks
1. Write V002–V013 exactly per doc 05 (column types, CHECKs, `+STD` columns, FKs with `ON DELETE` rules, partition keys in PKs).
2. For each table also write the canonical file in `tables/` and its indexes in `indexes/` with `COMMENT ON INDEX … IS 'serves: …'`.
3. Roles: passwords via Flyway placeholders; `ALTER ROLE app_rw SET statement_timeout='5s'`, `idle_in_transaction_session_timeout='10s'`; `REVOKE` table privileges from app roles; `api_definer` gets DML.
4. RLS: `ALTER TABLE … ENABLE ROW LEVEL SECURITY; ALTER TABLE … FORCE ROW LEVEL SECURITY;` + `own_rows` policy on every user-owned table (list in tests).
5. Seed with idempotent `INSERT … ON CONFLICT (code) DO UPDATE` (never delete referenced codes).
6. Drift check passes: migrations vs canonical folders.
7. Generate a 100-user synthetic dataset script stub `tools/seed_synthetic.py` (used from S08).

## DB objects created
All tables listed above; domains `common.safe_text`, `common.username`, `common.blind_index`, `common.ciphertext`, `common.positive_ml`; roles; partitions; RLS policies; seed rows.

## API endpoints
None.

## Screens
None.

## Security checks
SEC-4.2 roles least privilege · SEC-4.4 RLS forced · SEC-2 Layer 3 domains on all text columns · SEC-4.5 ciphertext columns for PII · no `public` schema usage · `app_rw` cannot `SELECT` any table (test).

## Input-validation checklist
- [ ] Every text column uses `common.safe_text` (or `common.username`) + `char_length` CHECK — verified by a pgTAP test that scans `information_schema.columns` for `text`/`varchar` columns not using an approved domain (allow-list of exceptions: generated columns, hashes, codes with their own regex CHECK).
- [ ] Every numeric health column has a range CHECK (height, weight, age, volume, temperature, duration, nutrients ≥ 0).
- [ ] Payload test: every payload inserted directly (as `migration_owner` in test) into each `safe_text` column raises `check_violation`.

## Tests to write (pgTAP)
schemas/roles exist; `has_table` for all; CHECK violations (boundaries: age 17/18/100/101, height 119.9/120/230/230.1, temp 14.9/15/40/40.1, volume 0/1/3000/3001/-100 rules); FK cascades; unique constraints (email_bidx, username lower, connection pair); RLS (`set_config('app.user_id', A)` cannot see B's rows as `api_definer`); `app_rw` permission denied on tables; partitions exist for current + 3 months; seed counts (17 nutrients, 8 drinks, 6 workouts, 8 goals, 4 activity levels, 3 body types); payload sweep.

## Acceptance criteria / Definition of done
- [ ] `flyway migrate` from empty succeeds on PG 18.6; re-run is a no-op.
- [ ] All pgTAP tests pass in CI; drift check passes.
- [ ] Every index has a comment describing the query it serves.
- [ ] Seed reproduces every constant in doc 06 (spot-checked by tests: 0.75/1.00/1.02/1.07, 1.55/1.85/2.20, 0.97/1.00/1.03, drink factors, sweat rates, 1500/6000 limits, 11 mL/kg, 0.85, 0.20, 2 %, 300 mL).
- [ ] No role except `migration_owner`/`api_definer` has table privileges.
- [ ] sqlfluff clean.

## Estimated effort
5–6 developer-days (DB/back-end engineer).

## Implementation status (2026-10-27)

Verified on a local PostgreSQL 18.6 + Flyway 13.11.1 + pgTAP 1.3.4 (native binaries, the same scripts CI runs: `tools/run_pgtap.sh`, `tools/drift_check.sh`).

| Acceptance criterion | Status |
|---|---|
| `flyway migrate` from empty succeeds; re-run is a no-op | ✅ 13 versioned + 5 repeatable migrations; re-run: "Schema is up to date" |
| pgTAP green; drift check passes | ✅ 676 assertions in 8 files; migrated and canonical schemas identical (3,455 lines) |
| Every index has a "serves" comment | ✅ enforced by `tests/030` |
| Seed reproduces every doc 06 constant | ✅ 63 constants in `calc_version 2026.1`; spot-checked by `tests/050` |
| Only `migration_owner`/`api_definer` have table privileges | ✅ enforced by `tests/010` |
| sqlfluff clean | ✅ (house style in `.sqlfluff`; 4 rules excluded with reasons) |

Built: 13 schemas, 18 domains (no column uses bare `text`), 6 roles, 68 tables (9 monthly-partitioned, 45 partitions), 65 commented indexes, 24 RLS policies, 5 seed scripts.

Defects the tests caught and fixed during the session:
- **V003** `ALTER DEFAULT PRIVILEGES FOR ROLE api_definer` failed (needs inherited membership); it was unnecessary and was removed.
- The **`safe_text` domain** let `&#0000060script&#0000062` through (entities without `;`); the regex now matches doc 07 R6.
- Two **domain regexes were corrupted** while writing the file (a lost backslash and literal bidi characters); the file is now generated ASCII-only, and CI rejects invisible characters.

Deviations from the plan (docs updated): RLS is **enabled, not forced** (doc 05 §7, doc 07 SEC-4.4); FKs into reference tables are not indexed (doc 05 §6); `ref.avatar` keyed by code (`avatar_code`); `user_id` added to `nutrition.saved_meal_item` and `sleep.night_waking` so RLS needs no joins; unconfirmed portion sizes flagged `is_confirmed = false` (new **OQ-59**); dev-only sample foods behind the `seed_sample_foods` placeholder.
