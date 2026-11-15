# Session 14 — Profile, Streaks, Notifications Centre, Reports (PDF), Help & Support, Offline Sync Hardening

## Goal and scope
Complete the Profile tab and remaining Settings: profile header counts, Active Streak (calendar, broken state, milestones), personal notification centre, Download Report (monthly STANDARD / custom STAR with AI insights), Report Preview/Downloaded/Share, Help & Support (FAQs, contact, report a problem with screenshot upload, request a feature, guide), and harden offline sync across all trackers (`/sync/changes`, conflict UX, multi-device).

**In:** streak procedures + job, `notify.notification` reads, `report` schema + worker PDF generation, `support` schema + upload pipeline, `/sync/changes`, mobile `features/profile`, `streak`, `reports`, `notifications`, `support`, sync engine polish.
**Out:** privacy export/deletion (S15).

## Prerequisites
S08–S13. Decisions/defaults: OQ-38, OQ-40, OQ-51.

## Files to create / modify

### naraacare-database
```
migrations/V0xx__report_support_tables.sql   # report.report_job; support.ticket, support.feature_request; RLS
functions/R__20_app.fn_streak_calendar.sql fn_profile_counts.sql
procedures/R__30_app.pr_recompute_streak.sql     # gaps-and-islands over user_activity_day; milestones → notification
functions/R__20_report.fn_report_data_hydration.sql fn_report_data_nutrition.sql fn_report_data_sleep.sql   # daily aggregates for range
procedures/R__30_report.pr_create_report_job.sql pr_update_report_job.sql
procedures/R__30_support.pr_create_ticket.sql pr_create_feature_request.sql
functions/R__20_sync.fn_changes_since.sql        # union of meals/intakes/workouts/sleep (incl. soft-deleted ids) by (updated_at, id) cursor, 7-day horizon
functions/R__20_notify.fn_notifications.sql procedures/R__30_notify.pr_mark_read.sql
views/R__40_report.v_daily_kpis.sql              # aggregated counts for the reporting role
tests/800_streak.sql tests/810_reports.sql tests/820_support.sql tests/830_sync.sql
```

### naraacare-backend
```
app/api/v1/routers/streak.py notifications.py reports.py support.py sync.py
app/schemas/*.py
app/domain/streak/service.py
app/domain/reports/builder.py        # ReportLab; all text XML-escaped; charts drawn natively (no HTML); disclaimer page
app/domain/reports/insights.py       # STAR: Claude summary of aggregates only (metered), output validated plain text
app/domain/support/uploads.py        # magic bytes, size ≤ 10 MB, Pillow decode with MAX_IMAGE_PIXELS, re-encode PNG/JPEG, strip EXIF, random key, object-storage put (encrypted at rest)
app/workers/jobs/generate_reports.py streak_rollover.py
app/integrations/storage.py (signed GET 5 min; filesystem in dev)  email.py (ticket forward template, autoescape)
tests/integration/test_streak.py test_reports.py test_support_upload.py test_sync_changes.py
tests/security/test_upload_security.py test_report_escaping.py
```

### naraacare-mobile
```
lib/features/profile/presentation/screens/profile_screen.dart widgets/{profile_header, counts_row}.dart
lib/features/streak/presentation/screens/{active_streak, streak_calendar}.dart
lib/features/notifications/presentation/screens/notifications_screen.dart
lib/features/reports/presentation/screens/{download_report, customize_report, report_preview, report_downloaded}.dart
lib/features/support/presentation/screens/{help_support, faqs, contact_support, report_problem, request_feature, guide}.dart
lib/features/settings/presentation/screens/legal_documents_screen.dart (Terms/Privacy/Licenses as native text; Licenses via LicenseRegistry + data sources incl. Open Food Facts, nutrition references)
lib/core/sync/* (pull changes, conflict banner "changed on another device", retry policy, background sync via WorkManager/BGTask)
test/features/** integration_test/offline_sync_test.dart
```

## Step-by-step tasks
1. Streak: `user_activity_day` already maintained by tracking procedures; `pr_recompute_streak` on change + hourly rollover per timezone; milestone notifications (doc 06 §5).
2. Profile header: Hi {name}, @username, STAR badge, counts (connections, streak, circles) from `fn_profile_counts`.
3. Notification centre: list (cursor), mark read, read-all; deep links validated.
4. Reports: `POST /reports` (idempotent) → job queued → worker loads aggregates → PDF (cover, summary %, daily averages, trends, insights if STAR, disclaimer) → object storage (7-day lifecycle) → notification "Report ready" → `GET /reports/{id}` signed URL → app downloads to device storage + share sheet. STANDARD: monthly only, hydration + nutrition (+ sleep for months they were STAR, OQ-38). STAR: custom range ≤ 366 days, + sleep + insights.
5. Help & Support: FAQ search (static JSON served by API), contact (mailto/tel), report a problem (category chips, description, optional screenshot), request a feature; tickets forwarded to the support inbox with escaped content.
6. Sync hardening: `/sync/changes` pull on foreground + after outbox flush; tombstones applied; conflicts → server copy wins + banner; exponential backoff; background sync (Android WorkManager, iOS BGAppRefresh); duplicate prevention verified.
7. Legal screens: render fetched policy text as plain text (or open in the external browser), never a WebView.

## DB objects
`report.report_job`, `support.ticket`, `support.feature_request`, functions/procedures/views above.

## API endpoints
`GET /me/streak`, `GET /notifications`, `POST /notifications/{id}/read`, `POST /notifications/read-all`, `POST /reports`, `GET /reports/{id}`, `GET /reports`, `GET /support/faqs`, `POST /support/tickets`, `POST /support/feature-requests`, `GET /sync/changes`.

## Screens (Figma frames)
`Profile`, `Connections` (link), personal `Notifications`, `Active Streak` (+ calendar, Streak Broken), `Download Report` (STANDARD/STAR), `Customize Report`, `Report Preview`, `Report Downloaded`, `Help & support`, `FAQs`, `Contact Support`, `Report a Problem`, `Request a Feature`, `Guide`, `Terms & Conditions`, `Privacy Policy`, `Licenses`.

## Security checks
T21 upload hardening; output encoding in PDFs (SEC-2.5); signed URLs short-lived, user-scoped keys; report/insight AI uses aggregates only; IDOR on reports/tickets/notifications; ticket text encrypted; email forwarding auto-escaped; rate limits (reports 10/day, tickets 5/day); sync endpoint returns only the caller's data.

## Input-validation checklist
| Field | App validator | Max | API type | DB |
|---|---|---|---|---|
| FAQ search | `search()` | 64 | SafeSearchQuery | — |
| Problem description | `freeText(2000)` | 2000 | SafeText(2000) | ciphertext |
| Screenshot file name | (system picker) | 100 | SafeFileName | key regex CHECK |
| Feature title | `shortText(120)` | 120 | SafeShortText(120) | safe_text(120) |
| Feature benefit | `freeText(1000)` | 1000 | SafeText(1000) | safe_text(1000) |
| Report month/range | pickers | — | date/Literal | CHECK range |
| Sync cursor | (opaque) | 256 | SafeOpaqueToken | — |
- [ ] PDF test: a user name/username containing every allowed punctuation renders escaped; payloads never reach the builder (rejected at input).

## Tests to write
Streak (consecutive days, gap, broken yesterday, timezone change, longest); report content correctness vs aggregates, tier rules, idempotency, expiry; PDF escaping; insights plain-text validation; uploads (valid PNG/JPEG, non-image, polyglot, 11 MB, decompression bomb, EXIF removed); sync (multi-device edits, tombstones, cursor paging, no duplicates after flaky network); widget tests per screen; E2E offline journey.

## Acceptance criteria / Definition of done
- [ ] Profile counts and streak calendar correct for seeded scenarios incl. "Streak Broken".
- [ ] Monthly report (STANDARD) and custom report with insights (STAR) generate ≤ 30 s and download/share on both platforms.
- [ ] Uploads are re-encoded and EXIF-free; malicious files rejected.
- [ ] Offline E2E: entries made offline appear exactly once after reconnect; another device's edit wins with a visible notice.
- [ ] All new text fields pass the 3-layer payload tests.

## Estimated effort
10–11 developer-days.
