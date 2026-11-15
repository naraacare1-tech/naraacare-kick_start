# Session 15 — Privacy: Consent Management, Data Export, Account Deletion, Retention

## Goal and scope
Implement DPDP-aligned privacy features: consent centre (view/withdraw/re-grant per purpose with policy versions), re-consent on policy updates, data export (ZIP of JSON + CSV), account deletion with 30-day grace and complete erasure workflow, retention jobs, in-app privacy notice and grievance contact, and data-minimisation verification.

**In:** `privacy.*` functions/procedures, `ops.pr_apply_retention` finalisation, `/privacy/*`, deletion worker, export worker, Apple token revocation, mobile `features/privacy`.
**Out:** legal text drafting (legal counsel, OQ-47).

## Prerequisites
S05–S14 (all data stores exist so export/deletion can cover them). Decisions: OQ-47 (grace 30 days, legal docs), OQ-48 (retention), privacy notice draft available.

## Files to create / modify

### naraacare-database
```
functions/R__20_privacy.fn_current_consents.sql fn_requires_reconsent.sql
functions/R__20_privacy.fn_export_<schema>.sql  (one per schema: profile, nutrition, hydration, activity, sleep, social (own messages/circles), ai (own conversations), billing (own transactions), notify, consents)
procedures/R__30_privacy.pr_request_export.sql pr_complete_export.sql
procedures/R__30_privacy.pr_request_deletion.sql   # status pending_deletion, scheduled_for = now()+30d, revoke tokens
procedures/R__30_privacy.pr_cancel_deletion.sql
procedures/R__30_privacy.pr_delete_user.sql        # ordered hard delete across schemas; anonymise billing/consent (hash user id); circles: leave + succession; messages: delete bodies; audit rows retained without PII
procedures/R__32_ops.pr_apply_retention.sql        # (finalise) per privacy.retention_policy
seed/R__15_seed_retention_policy.sql
tests/900_privacy_*.sql   # after pr_delete_user no row references the user id except anonymised billing/consent; export covers every user-owned table (catalog scan)
```

### naraacare-backend
```
app/api/v1/routers/privacy.py (complete)  app/schemas/privacy.py
app/domain/privacy/export.py            # build ZIP: README.txt, JSON per domain, CSV (formula-injection guard), decrypted own PII; object storage + signed URL 15 min
app/domain/privacy/deletion.py          # re-auth (password or OTP), schedule, cancel on sign-in during grace (explicit confirm), finalisation hooks
app/integrations/apple_revoke.py        # revoke Sign in with Apple tokens on deletion
app/workers/jobs/process_deletions.py generate_exports.py apply_retention.py
tests/integration/test_consents.py test_export.py test_deletion.py test_retention.py
tests/security/test_privacy_security.py   # export of another user impossible; deletion requires re-auth; signed URL expiry
```

### naraacare-mobile
```
lib/features/privacy/presentation/screens/{privacy_centre, consent_detail, data_export, delete_account, delete_confirm, deletion_scheduled}.dart
lib/features/privacy/presentation/reconsent_gate.dart     # blocks app use until re-consent when policy major version changes
lib/features/settings/... (Account → Delete Account; Settings → Privacy)
local data wipe on logout/deletion (drift DB, secure storage, cached files)
test/features/privacy/**
```

## Step-by-step tasks
1. Consent centre: list purposes with status, policy version and date; toggles for optional purposes (`ai_processing`, `circle_sharing`, `marketing`); withdrawal of `ai_processing` disables Rin and the drink estimator immediately; withdrawal of `health_data` = account deletion path (explain).
2. Re-consent: `fn_requires_reconsent` on launch; `reconsent_gate` shows the changes summary and links to the full text.
3. Export: request (1 per 24 h) → worker assembles all user data (catalog-driven coverage test ensures no table is missed) → ZIP to object storage (encrypted at rest, 7-day lifecycle) → notification → signed link (15 min) → app downloads/shares.
4. Deletion: re-auth → schedule (+30 days) → revoke all sessions and push tokens → notify by email → sign-in during grace offers "Cancel deletion" → worker `process_deletions` runs `pr_delete_user`, deletes stored files (reports, exports, attachments), revokes Apple tokens, cancels nothing in stores (user informed to cancel subscriptions; the app shows a store link before confirming) → deletion receipt email (to the address captured before deletion) → final purge of the address.
5. Retention: seed `privacy.retention_policy` (doc 05 §9), finalise the job, monitoring metric of rows purged.
6. Privacy notice screen (plain language, itemised data + purposes + processors + grievance officer contact) and the medical disclaimer locations audited.
7. Data-minimisation audit: confirm no mobile number, DOB, location, contacts collected; Sentry/log scrubbing verified with a canary test.

## DB objects
Functions/procedures above; retention seed.

## API endpoints
`GET /privacy/consents`, `POST /privacy/consents`, `POST /privacy/exports`, `GET /privacy/exports/{id}`, `POST /privacy/deletion-request`, `DELETE /privacy/deletion-request`.

## Screens (Figma frames)
`Account` → Delete Account, Settings Privacy (new; follows Settings list style), consent sheet (from S07), Terms/Privacy (S14). New frames need design sign-off: Privacy Centre, Data Export, Delete Account confirm/scheduled.

## Security checks
SEC-7.1–7.6; T23 (append-only consent with versions); re-auth before deletion/export; exports only for the caller, short signed URLs, encrypted at rest; deletion completeness test; CSV formula-injection guard; Apple token revocation (App Store requirement); audit entries for privacy actions.

## Input-validation checklist
- [ ] `purpose` Literal; `policy_version` SafeShortText(20); `password` SafePassword or `code` SafeOtp for re-auth; `Idempotency-Key` UUID.
- [ ] Export CSV writer escapes formula-leading characters; JSON is serialised (no string concatenation).
- [ ] Payload sweep covers the new endpoints.

## Tests to write
Consent append-only (UPDATE/DELETE fail); withdrawal effects (Rin 403 `CONSENT_REQUIRED`); re-consent gate; export completeness (catalog scan: every table with `user_id` is represented), content decrypted correctly, link expiry; deletion grace + cancel; `pr_delete_user` leaves no references (catalog scan) except anonymised rows; circle succession on deletion; stored-file cleanup; retention purge counts; mobile local wipe.

## Acceptance criteria / Definition of done
- [ ] A user can view/withdraw consents; withdrawal takes effect immediately server-side.
- [ ] Export ZIP contains all personal data in readable JSON/CSV within 1 hour of request.
- [ ] Deletion completes after 30 days (time-travel test) with no residual personal data in DB, object storage, or Redis; receipt sent.
- [ ] Retention job enforces doc 05 §9 (after legal approval).
- [ ] Privacy notice and grievance contact available in-app.

## Estimated effort
7–8 developer-days.
