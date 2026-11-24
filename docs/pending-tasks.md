# Pending tasks by session

Last updated: 2026-11-02. One place to see what is still open in each session.
Details live in each session's "Implementation status" section and in
`00-open-questions.md` (OQ-nn). Tick an item (`[x]`) when it is done, then remove it
at the next update.

**Across all sessions**
- [ ] Nothing is committed or pushed yet (all three repos are local `git init` only).
- [ ] Create the GitHub repos, branch protection and real CODEOWNERS teams (owner action); the first CI run happens after the push.
- [ ] Figma: the Starter-plan MCP limit blocks screenshots, variables and asset export (OQ-01). Needs an upgraded seat or a manual export.
- [ ] **Tests deferred (owner decision, 2026-11-02):** from Session 09 to the end, sessions are built without writing new tests. Each session below has a "Tests to write later" list; write them in one pass (or in Session 16) before release.

---

## Change 2026-11-03: plain-text storage, no Redis in the API (done)
Owner request. The database stores email, OTP, names, condition codes, installation ids, IPs, push/purchase tokens and the Apple refresh token in plain text. Only passwords and refresh tokens are hashed. The API no longer uses Redis: no entitlement or purchase cache; rate limits, the logout list and lockout-email dedupe are in memory. Doc 07 §6.1 and OQ-74 have the details.
- [x] Database: canonical tables/domains changed, baseline migrations V002/V005/V006/V009/V010/V011 regenerated, V016/V020 emptied (folded in), routines and pgTAP fixtures updated; 20/20 pgTAP files pass, no drift.
- [x] Backend code: crypto module, DEK tool and field-encryption settings removed; `REDIS_URL` worker-only; ruff clean.
- [ ] **Owner:** rebuild your local database (Flyway `clean` + `migrate`, or drop and recreate it). The changed baseline migrations no longer match an already-migrated database.
- [ ] **Owner:** Windows blocks the uv-managed Python 3.13 (exit `0xC0E90002`, Smart App Control / code integrity). Allow it, or install Python 3.13 from python.org and recreate `.venv`. Until then mypy, sqlfluff (`uv tool run`) and the API cannot run on this machine.
- [ ] Run mypy, sqlfluff and an API smoke test once Python runs again.
- [ ] Tests to update later (they still use the old encrypted/Redis shapes): `tests/conftest.py`, `tests/integration/{flows,test_auth_flow,test_db,test_hydration,test_oauth_flow,test_profile_flow}.py`, `tests/unit/core/{test_hashing,test_oauth,test_rate_limit,test_tokens}.py`, `tests/unit/domain/hydration/test_push_and_estimate.py`, `tests/unit/test_entitlements.py`; add a unit test for `app/core/memory_store.py`. `tests/unit/core/test_crypto.py` was deleted with the module.

## Session 01: Foundations, repos, tooling, CI
- [ ] GitHub repos + protected `main` + CODEOWNERS (placeholder teams are commented out).
- [ ] iOS flavors: run `tool/ios/setup_flavors.rb` once on a Mac.
- [ ] Release APK build only verified in CI (no Android SDK locally).
- [ ] First green CI run (gitleaks, all checks) after the push.
- [ ] Android release signing (deferred to S17).

## Session 02: Database schemas, tables, seed
- [ ] OQ-59: product/nutritionist to confirm the proposed portion sizes (`is_confirmed = false`).
- [ ] Real food data replaces the dev-only sample foods (`seed_sample_foods`); licensing (OQ-42).

## Session 03: Database functions, procedures, audit
- [ ] OQ-60: security/product to choose strict refresh-token reuse (current default) or a ~10 s grace window.

## Session 04: Backend core, security, validators
- [ ] Backend CI database job (checks out `naraacare-database` at `DATABASE_REF`) has never run: needs the GitHub repos.
- [ ] OQ-61: chat emoji with joiners; resolve in S12 (recommended: chat stored as ciphertext).

## Session 05: Auth and user profile
- [ ] OQ-26: approve the sign-up "already registered" copy.
- [ ] OQ-12 / OQ-13: nutritionist sign-off on TDEE multipliers and the activity mapping.
- [ ] OQ-33: the medical-condition / allergy list from product.
- [ ] Referral code at sign-up (moved to S11).

## Session 06: Flutter foundation
- [ ] OQ-01 / OQ-57: replace the sampled colour tokens with an official Figma token export; confirm font families.
- [ ] mitmproxy pinning check on a staging build (needs staging).
- [ ] OQ-66: ops sign-off on leaf SPKI pinning.
- [ ] Golden tests (deferred to design QA, need a Linux-rendered baseline).

## Session 07: Flutter onboarding and auth
- [ ] Figma pixel review of every frame + golden tests (blocked by the MCP limit).
- [x] Avatars (2026-11-03): male/female figures from `D:\Figma images` (full resolution from the Figma PDFs) in `naraacare-mobile/assets/avatars/`: water (blue), food (mint) and neutral looks on Home, and the real figures in onboarding step 1 and the intro. Rebuild with `tools/pdf_images.py` + `tools/make_avatars.py`.
- [ ] OQ-56 (rest): body-type variants (3 per sex), sleep-state look, and the other state variants (energy/hydration bands) are not in the exports yet; one figure per sex is used for every body type. Other illustrations still use icons.
- [ ] OQ-67: Apple sign-in on Android (needs an API callback route) or keep iOS-only.
- [ ] OQ-68: step 6 should set `avatar_code` server-side (small backend change).
- [ ] OQ-69: owner sign-off on the forgot-password "If an account exists…" copy.
- [ ] Patrol E2E against staging (real inbox, Google, Apple): S16.
- [ ] Settings entries shown disabled until their sessions: notifications (S13), subscriptions (S14), referrals (S11), help and delete account (S15).

## Session 08: Nutrition tracking (in progress)
Database and backend are done and verified (17/17 pgTAP files, no drift; 593 backend tests, 96.7 % coverage).

Mobile:
- [ ] Fix the 18 failing tests from the last full run (`flutter test`). Most are in router, auth, home/settings, onboarding and the sign-up flow, and appeared after the test harness change (fake connectivity/voice/scanner). One is in `nutrition_test.dart` (N1/N2 Home), one is in `payload_fields_test.dart` (username).
- [ ] Run and get the rest of `test/features/nutrition/nutrition_test.dart` green.
- [ ] Payload widget tests for the new fields: food search box, saved-meal name, voice transcript, barcode.
- [ ] `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, full `flutter test` green.

Backend:
- [ ] Optional: Semgrep run over the new nutrition code.

Docs:
- [ ] Session 08 "Implementation status" section.
- [ ] Doc 04: `?dry_run=true`, `If-Match` required on PUT/DELETE, 200 on replay, `limit` in `DAILY_LIMIT_REACHED`, `SAVED_MEAL_LIMIT`, staff IP allow-list, packaged foods.
- [ ] Doc 08: `STAFF_IP_ALLOWLIST`.
- [ ] Doc 00: new OQs: barcode products become `packaged` foods (missing nutrients stored as 0); Android speech may use Google's recogniser (OQ-43); the Figma info sheet "[Decide]" BMI line; `/meals?date` without a cursor.

Decisions waiting for the owner:
- [ ] OQ-02: confirm the reconstructed BMR/TDEE formulas.
- [ ] OQ-16: approve the exercise MET values.
- [ ] OQ-42: food database licensing (legal, before launch).
- [ ] Info sheet BMI line marked "[Decide]" in Figma.

## Session 09: Hydration and reminders (code complete)
Database, backend and mobile are built; docs and the implementation status are written (see the session file). What is left:
- [ ] Firebase projects per flavor (owner action) and the service-account key in the secret manager.
- [ ] Mobile push implementation behind `PushService` (firebase_messaging + flutter_local_notifications at the doc 03 pins), the Android 13 notification permission, and the local offline reminder fallback; then device registration works end to end.
- [ ] OQ-70 (push text localisation), OQ-71 (reminder defaults and quiet hours sign-off).

Tests to write later:
- [ ] Backend: full suite with coverage and the payload sweep over the new fields (the last full run was interrupted); keep coverage >= 95 % and `app/core/security` >= 95 %.
- [ ] Backend: `GET /hydration/status` p95 <= 150 ms with 90 days of data.
- [ ] Backend: worker jobs end to end as the `app_worker` role (FCM mocked).
- [ ] Mobile: widget tests for the gesture and every avatar state, the sheets, edit/409, STAR upsell, permission explainer; offline replay idempotency; payload widget tests (water amount, drink search, custom drink name, workout duration).
- [ ] Device check: reminders arrive on Android and iOS test devices at the configured times, with no health values.
- Already written and green: pgTAP `300_hydration`, `310_activity`, `320_notify`; backend unit `tests/unit/domain/hydration/*`; integration `tests/integration/test_hydration.py` (9 tests).

## Session 10: Sleep avatar (code complete)
Database, backend and mobile are built; docs and the implementation status are written. What is left:
- [ ] Figma pixel review of the sleep screens (blocked by the Figma MCP limit).
- [ ] OQ-23: product to confirm the buffers (15/15/10 min), the goal by age and the label thresholds.
- [ ] Tests to write later (pgTAP `400_sleep`, backend unit + integration, mobile widget): DOC example 450 min / 94 %; FIG 7h45 -> 97 %; one waking -> 420 min / 88 %; 16 h boundary (16 h ok, 16 h 1 min rejected); buffers exceeding the duration -> 0; multiple entries summed (nap); overlap rejected; STANDARD 403; last-2 edit; an entry crossing midnight belongs to the wake date; widget tests (locked vs unlocked, wheels, waking rows); payload tests.

## Session 11: Tiers, subscriptions, referral (code complete)
Database, backend and mobile are built; docs and the implementation status are written. What is left:
- [ ] Owner: Play Console + App Store Connect products `star_monthly` / `star_yearly` (OQ-06 prices), the Play service account (GOOGLE_PLAY_SERVICE_ACCOUNT_JSON), the App Store in-app purchase key, the Pub/Sub topic and push subscription for RTDN, App Store Server Notifications v2 URLs (sandbox + production), license / sandbox testers.
- [ ] Download Apple Root CA - G3 into `naraacare-backend/certs/` (see its README) and verify its SHA-256.
- [ ] Sandbox purchase check on both platforms (unlock within 5 s), webhook check within 1 minute.
- [ ] Deep-link domain files on the landing site (`naraacare-mobile/deeplink/`), Play signing SHA-256 and Apple team id; iOS Associated Domains (OQ-73).
- [ ] OQ-39 referral link domain and rules sign-off; OQ-72 billing amounts / invoices.
- [x] Subscription screens rebuilt to Figma (2026-11-05, "My subscriptions 1-7"): plans with Monthly/Yearly toggle and STANDARD/STAR cards, Upgrade to STAR (billing cycle, start/renewal dates, Confirm & Subscribe), You're now on STAR plan, STAR My Subscriptions (plan card, includes, actions), Billing History, Cancel Subscription (finishes in the store, then Subscription Cancelled on return). Prices: store price when the store answers, else `GET /billing/plans` INR display price; yearly saving computed from the two plans. "Update Payment Method" opens the store page (OQ-07). Kept although not in Figma: Restore purchases (store rule). Left out: the Figma "Download Invoice" page (the frame says "sample generated with AI"; OQ-72).
- [ ] Widget tests for the new subscription screens: toggle switches prices and suffix; fallback price when the store has no products; Confirm & Subscribe with no store product shows the toast; verified purchase goes to the success page; STAR view hides Cancel once cancelled; cancel screen pushes Subscription Cancelled when the re-read shows auto-renew off; `_addMonths` (31 Jan -> 28/29 Feb, Dec -> Jan).
- [ ] Tests to write later (pgTAP `500_billing`, `510_referral`, backend unit + integration + security, mobile widget): Google/Apple verification with recorded sandbox fixtures (valid, expired, refunded, wrong package/bundle, tampered JWS); token reuse across accounts; idempotent verify; webhook replay; forged webhook -> 401 and no change; entitlement transitions (active -> canceled -> expired, grace, refund -> immediate STANDARD); cache invalidation; referral rules (self, duplicate device, > 7 days), tally (29/30/31 active days, 60-day window), reward once, grant after the paid period; sandbox purchase E2E on both platforms.

## Session 12: Social, care circles, chat (in progress)
- [x] Database (2026-11-03): migration V021 (social schema, 9 tables incl. 2 partitioned, member-based RLS, `notify.circle_notification_preference`), 54 social routines (people/connections/blocks, circles, invites, invite links, chat with mentions, feed, member avatars, notifications), activity events emitted by water/meal/sleep logs and the water goal. Chat is plain text; invite-link tokens are hashed. 20/20 pgTAP files pass, no drift, and an end-to-end scratch run of the flow passed. Your local database is at V021.
- [x] Database additions (2026-11-03): `notify.fn_notifications` / `pr_mark_notifications_read` (in-app list, circle filter) and `ops.fn_social_pushes` (worker). Fixed: the meal and sleep feed events passed a subquery to CALL (0A000), which made every meal/sleep log dated today fail; pgTAP had not caught it because its entries are not dated today.
- [x] Backend (2026-11-03): routers `/people`, `/connections`, `/blocks`, `/circles` (members, role, shares, feed, avatars, notification settings, invite links), `/circle-invites`, `/invite-links/resolve`, `/circles/{id}/messages`, `/notifications`, `/realtime/ticket`, `GET /ws`; in-memory tickets (single use, 30 s) and fan-out (no Redis; the API runs as ONE process); worker job `notify.send_social_pushes` with generic texts. New error codes (ADMIN_REQUIRED, CIRCLE_FULL, LAST_ADMIN, INVITE_LINK_EXPIRED/LIMIT, QUERY_TOO_SHORT, SHARES_INVALID, MENTION_INVALID, TOO_MANY_MENTIONS/INVITEES); USERNAME_REQUIRED now answers 403. New dependency `websockets==17.3` (uvicorn needs it to serve WebSockets). A scratch end-to-end run of the whole flow through the real app and database passed.
- [x] Python works on this machine again: the existing test suite was repaired after the plain-text / no-Redis change (fixtures, ciphertext checks turned into plain-text checks, a `CAST(:ip AS inet)` that the `db_call` guard rejected at import).
- [ ] Not yet: `feed.event` over the WebSocket (the feed refreshes on open/pull); `INVITE_LINK_TTL_DAYS` is not read (the database fixes 7 days); scaling past one API process needs a shared broker for tickets and fan-out.
- [x] Mobile (2026-11-03): Your Circles (invites, list, create tip), Create a Circle -> Add Members (connections / username search, Invite Link) -> Share with (>= 1 avatar, sleep STAR), circle home (members, chat card, Recent Updates), chat with @mentions and live updates (WebSocket over a pinned HttpClient upgrade, ticket per connect, reconnect with backoff), All / Manage Members (make / remove admin, remove), member avatars, Settings (leave dialog), notification switches, Name & Picture, circle notifications, invite screen and `/circle/<token>` links, Connections (Profile and Your Circles). Checked on the emulator against the real backend: create circle, chat send. `/circle/*` added to the iOS deep-link file.
- [x] Home (2026-11-03): avatar carousel with dots, round side actions (more / info), one primary button per page, colour fill that rises with the server level and animates on each log.
- [ ] Not yet: share button on Home (needs `share_plus` + what to share: avatar image with watermark?); wallpaper art (gradients for now); feed.event live.
- [ ] Deviations to confirm: suggestions use circle co-members only (friends-of-connections needs cross-user reads; later); goal-completion notifications exist for water only (food/sleep have no "goal" event in the business rules yet).
- [ ] Open inputs: OQ-35, OQ-36, OQ-41, OQ-61.
- [ ] Tests to write later: circle cap 50 under concurrent accepts; >= 1 share enforced; sleep share STAR-only for sharer and viewer; unshare hides past feed items; admin succession; a removed member loses access at once (REST + WS); blocked users cannot search/invite/mention; invite link expiry/max uses/revoke; message idempotency; mention of a non-member rejected; WS ticket single use + expiry; WS frame size/budget/unknown frames; mobile widget tests for every Care Circle screen and the Home carousel (existing Home/nutrition widget tests need updating for the moved buttons); typing relayed only to members; push payload content and job cursor/dedup; notifications list circle filter (non-member 404) and mark-read; IDOR suite for every circle route; widget tests; two-device chat E2E; payload tests (chat, circle names); pgTAP file 600_social for the routines (the scratch flow in the S12 notes is the starting point).

## Session 13: Rin AI (in progress)
- [x] OQ-37 approved (2026-11-03): Claude `claude-opus-5-5`, own data only, 100k tokens/user/day, transfer to Anthropic with `ai_processing` consent.
- [x] Database (2026-11-03): migration V022 (`ai` schema: conversation, message, memory_summary, pending_action, usage_event; own-row RLS), routines `ai.fn_require_rin` (STAR + consent + onboarding gate in the database), `fn_rin_context` (age band, sex, goals, today, last 7 days, memory; no name/email/exact age/other users), usage, conversations (+ text search), messages, history, pending actions (24 h, accept once), delete chat, memory. Chats are titled from their first prompt. 20/20 pgTAP, no drift, scratch flow passed. Your local database is at V022.
- [x] Backend (2026-11-03): `/rin/usage`, `/rin/conversations` (list/search, create, messages, SSE send, delete), `/rin/actions/{id}/accept|dismiss`, `DELETE /rin/memory`. Guardrails: emergency phrases (English/Hinglish) get a fixed reply with 112 / 108 / Tele-MANAS 14416 and no model call; model output is cleaned to plain text before it is streamed, stored or shown. Tools `propose_meal_log` / `propose_drink_log` (strict) create pending actions only; meals are matched to the food database and priced with the normal preview; accepting logs through the normal meal / intake path with source `rin`. Every model turn's tokens are recorded; 403 DAILY_LIMIT_REACHED at 100 %. A scripted end-to-end run passed (gates, streaming, markup removal, replay, meal card -> accept -> meal logged, accept twice -> 409, emergency, cross-user 404, delete).
- [x] Mobile (2026-11-03): Rin AI tab: Unlock Rin AI (STANDARD), Start (greeting + 4 suggestions), chat with streaming replies, usage bar, disclaimer, meal / drink card (Add to Avatar / Edit amounts / Not Now), menu (Search History, Help, Delete Chat + toast), Search, Help (+ clear memory), consent prompt when `ai_processing` is missing.
- [ ] Owner: a real `ANTHROPIC_API_KEY` in the backend `.env` (without it Rin answers "resting"); Anthropic workspace spend limits; privacy notice text for the AI processor and the transfer.
- [ ] Deviations / later: no server-side refusal fallback (beta; refusals get a fixed friendly reply); memory summaries are stored and cleared but not generated automatically yet; titles from the first prompt (no model call); drink estimator / voice parse do not yet draw on the allowance; `ai` tables are not partitioned; no live eval harness yet.
- [ ] Tests to write later: guardrails (emergency phrases English/Hinglish -> fixed response, no model call); output sanitiser (tags, markdown, entities, schemes -> plain text); context builder excludes other users and PII; metering (limit -> 403 DAILY_LIMIT_REACHED, reset at local midnight, cache-write counted); pending action lifecycle (accept -> meal logged with source rin, limit enforced, dismiss, expiry, accept twice); STANDARD 403; missing consent 403 CONSENT_REQUIRED; SSE incl. refusal and mid-stream error; IDOR on conversations/actions; pgTAP `700_ai`; widget tests for the Rin screens; evals (meal mapping >= 85 %, 100 % emergency handling, 0 cross-user leaks, 0 markup outputs).

## Session 14: Profile, streaks, reports, sync (in progress)
- [x] Decisions (2026-11-05): reports are shared through the system share sheet (`share_plus`); offline sync runs in the foreground (open / resume / reconnect / after an offline entry, with backoff); background sync moves to S17. OQ-38, OQ-40, OQ-51 applied as their defaults.
- [x] Database (2026-11-05): migration V023 (`report.report_job`, `support.ticket`, `support.feature_request`, own-row RLS); streak routines (`app.fn_streak_runs`, `app.fn_streak`, `app.pr_recompute_streak` run by a trigger on new active days; milestone notifications at 3/7/14/30/60/100/365, the highest one crossed once; a stale cache reads as 0, so no rollover job); `fn_get_profile` now returns connection and circle counts; reports (`report.pr_create_report_job` with tier / consent / OQ-38 / 10-a-day rules, `report.fn_report_jobs`); support (`support.pr_create_ticket`, `pr_create_feature_request`, 5 a day); sync (`app.fn_changes_since`, cursor by (updated_at, id), last 8 days, incl. deletions); worker routines in `ops` (claim / days / insight usage / finish / expire reports; support forwarding feed); `billing.fn_entitlement_of` (internal, no actor check) behind `fn_current_entitlement`; BI view `report.v_daily_kpis` (counts only, user counts hidden below 5) for the `reporting` login; push fan-out covers streak milestones and reports. 20/20 pgTAP, no drift, scratch flow passed. Your local database is at V023.
- [x] Backend (2026-11-05): `GET /me/streak`, `POST/GET /reports`, `GET /reports/{id}`, `GET /reports/{id}/file` (owner only, no public URL while there is no object store), `GET /support/faqs`, `POST /support/tickets` (multipart; screenshot magic bytes, 10 MB, pixel cap, decoded and re-encoded without EXIF, random key), `POST /support/feature-requests`, `GET /sync/changes`; `/me` counts filled. PDF builder (ReportLab canvas only: no markup parsing; summary, daily averages, trend charts, insights, disclaimer page); STAR insights from period averages only (structured output, plain-text cleaned, metered as `report_insight`). Worker jobs `reports.generate` (every minute), `reports.expire` (hourly), `support.forward` (every 5 min, plain-text email to `SUPPORT_INBOX_ADDRESS`, Reply-To = account email). New packages: reportlab 5.1.0, pillow 12.3.0, python-multipart 0.0.32. Scripted end-to-end run passed; full suite 612 passed (+2 payload-sweep findings fixed with `SafeYearMonth`).
- [x] Mobile (2026-11-05): Profile tab (name, @username, STAR badge, bell, settings, avatar, connections / streak / circles counts), Active Streak (+ Streak Broken), streak calendar, personal Notifications (Today / Earlier, links through an allow-list), Download Report (monthly, custom for STAR, STAR upsell, recent reports), Customize Report, Report Preview (polls until ready), Report Downloaded (+ share sheet), Help & support, FAQs (search), Contact Support (email; phone for STAR), Report a Problem (categories, description, screenshot from the gallery with a fixed file name), Request a Feature, Guide; Licenses now credit Open Food Facts (ODbL) and the nutrition references. Sync: pull after every flush with a stored cursor, server copy wins with a "changed on another device" banner, retry backoff, flush on resume. New packages: share_plus 13.3.1, image_picker 1.2.4 (iOS photo-library text added). `flutter analyze --fatal-infos` clean.
- [x] Emulator check (2026-11-05, after a cold boot of the frozen emulator): Profile tab with real counts, Active Streak in the Streak Broken state, calendar, Download Report (STANDARD), month picker (fixed to open above the tab bar), Report Preview polling, Help & Support, FAQs, Contact Support (email only for STANDARD), Report a Problem, Request a Feature sent to the local database. Not seen in the app: a finished PDF (the worker needs Redis locally; the worker path passed in the scratch end-to-end run).
- [x] Local report worker (2026-11-05): without Redis the taskiq worker can't start, so reports stayed "queued". Owner chose a dev-only runner: `naraacare-backend/tools/dev_worker.py` runs reports / exports / support forwarding every 10 s and the expiry jobs every 10 min, with the app_worker login from the environment; refuses outside APP_ENV=dev. Report Preview now says "taking longer than usual" after a minute and polls every 10 s instead of 2 s.
- [ ] Test for `tools/dev_worker.py`: refuses without an app_worker DATABASE_URL and outside dev; a queued report becomes ready after one loop.
- [ ] Owner: FAQ answers (draft written from the product docs, `app/domain/support/faqs.py`); support phone number and hours (`SUPPORT_PHONE`, `SUPPORT_PHONE_HOURS`, shown to STAR only), public support email (`SUPPORT_CONTACT_EMAIL`); Guide wording (the Figma frame is empty).
- [ ] Deviations / later: Report Preview shows the period and sections but not the "78 % goal achieved" numbers (the numbers are in the PDF; showing them before download needs a stored summary, V024); names with characters outside Latin-1 print as "?" in the PDF (needs a bundled Unicode font); deleting every entry of a day does not remove it from the streak (activity days are not cleared on delete); screenshots are not attached to the support email (support opens them from admin tools, S16); background sync in S17; existing users' streak cache fills on their next active day (the streak screen computes it live).
- [ ] Tests to write later: streak (consecutive days, gap, broken yesterday, timezone change, longest, milestone crossed by a multi-day insert); report totals vs aggregates, tier rules (custom / sleep OQ-38 / insights consent), idempotency (202 then 200), daily limit, expiry, file owner-only; PDF escaping (every allowed punctuation in names, non-Latin-1); insights plain-text validation (tags, markdown, schemes dropped) and metering; uploads (valid PNG/JPEG, non-image, polyglot, 11 MB, decompression bomb, EXIF removed, unknown form field); support forwarding (plain text only, retry, give-up after 20); sync (multi-device edits, tombstones, cursor paging, bad cursor 422, no duplicates on a flaky network, conflict banner); pgTAP `800_streak`, `810_reports`, `820_support`, `830_sync`; widget tests for the new screens; offline journey E2E.

## Session 15: Privacy, consent, export, deletion (in progress)
- [x] Decisions applied (2026-11-05): doc 05 section 9 defaults (OQ-48, legal approval still pending): billing transactions and consent proof kept 8 years with the user id hashed (archive tables), deleted chat messages purged after 30 days, inactive Rin chats after 12 months, token usage after 13 months, support screenshots after 180 days. 30-day deletion grace (OQ-47). The account stays active during the grace period (a scheduled deletion request is the source of truth) so the user can sign in and cancel.
- [x] Database (2026-11-05): migration V024 (`privacy.consent_archive`, `billing.transaction_archive`, `privacy.deletion_log`, RLS with no policy; export_request attempts/size/error, deletion_request receipt_sent_at). API routines `privacy.fn_privacy_status` (deletion, policies needing re-consent by major version, latest export), `fn_exports`, `pr_request_export` (idempotent, 1/24 h), `pr_request_deletion` (30 days, revokes refresh and push tokens), `pr_cancel_deletion`; `pr_record_consent` refuses withdrawing terms / privacy / health_data (deletion path). Worker routines in `ops`: catalog-driven `fn_export_user` (every table with a user column, secrets excluded), export claim/finish/expire, `fn_due_deletions`, `fn_user_files`, `pr_delete_user` (archives hashed, circles handed to the earliest member, user id removed from other people's rows and notification params, account deleted with cascades, audit values/keys scrubbed last), `fn_apply_row_retention`, `fn_expired_attachments`; retention seed extended. 20/20 pgTAP, no drift. Scratch erasure: a catalog scan of every uuid/text/jsonb column finds no trace of the user's id, email or name afterwards. Your local database is at V024.
- [x] Backend (2026-11-05): `GET /privacy/status`, `POST /privacy/reauth` (email code for accounts without a password), `POST /privacy/exports` (+ re-auth, Idempotency-Key), `GET /privacy/exports/{id}` and `/file` (owner only), `POST/DELETE /privacy/deletion-request` (+ re-auth; current sessions blocked at once; "scheduled" email). Export ZIP: README, JSON per table, CSV per table with a formula-injection guard. Worker jobs `privacy.generate_exports`, `expire_exports`, `process_deletions` (Apple token revocation, file deletion, receipt email once, erasure), `apply_retention` (counts logged as the metric). New setting `APPLE_REVOKE_URL`. Scripted end-to-end run passed (re-auth by wrong password / password / code, export -> ZIP contents, limit, required-consent block, deletion -> session ended -> cancel -> reschedule -> time travel -> erasure + receipt + files gone).
- [x] Mobile (2026-11-05): Settings > Privacy (consents with version and date, toggles for AI processing / circle sharing / marketing, required ones explained), Download my data (re-auth sheet, progress, download + share), Privacy notice (plain-language draft with processors, retention, rights, grievance contact), Account > Delete Account (what is deleted, 30 days, store subscription warning with manage link, confirmation, re-auth), launch-time takeovers for a scheduled deletion (Cancel deletion / keep and sign out) and for policy updates (accept new versions); local data wipe on every sign-out (outbox, local entries, cached status, sync cursor, downloaded reports/exports). Data-minimisation audit: no location, contacts, phone number or date of birth collected. Emulator: Privacy centre, notice, export and delete screens checked (export/delete block screenshots by design).
- [ ] Owner / legal: approve the retention periods (OQ-48) and the privacy-notice wording (OQ-47); name the grievance officer and contact address (the notice shows the support email until then); publish the real Terms / Privacy documents in `ref.policy_document` (the re-consent gate starts working once a published version exists); design sign-off for the new privacy screens (no Figma frames); Sign in with Apple key for token revocation.
- [ ] Deviations / later: export files are served by an authenticated API route (no object store or signed URLs yet); audit-trail scrubbing scans `audit.change_log` per erasure (fine for nightly batches; revisit with an index at scale, S17); the deletion receipt is sent just before erasure, so a crash between them could repeat the erasure attempt but not the email; no in-app Sentry yet, so the log-scrubbing canary test waits for S16/S17.
- [ ] Tests to write later: consent append-only (UPDATE/DELETE fail); required-consent withdrawal blocked; withdrawal effects (Rin 403 CONSENT_REQUIRED, drink estimate default); re-consent gate (major version only, drafts ignored); re-auth (password, code, wrong code, another user's code); export completeness (catalog scan: every table with a user column is exported or explicitly excluded), no secrets, CSV formula guard, owner-only file, expiry; deletion grace + cancel + time travel; `pr_delete_user` catalog scan leaves no references; circle succession and last-admin promotion; archives hashed; stored-file cleanup; Apple revoke called; retention purge counts; mobile local wipe; payload sweep over the new endpoints.
- [ ] Tests to write later: consent append-only (UPDATE/DELETE fail); withdrawal effects (Rin 403 CONSENT_REQUIRED); re-consent gate; export completeness (catalog scan of every table with user_id), decrypted content, link expiry; deletion grace + cancel; `pr_delete_user` leaves no references except anonymised rows; circle succession on deletion; stored-file cleanup; retention purge counts; mobile local wipe.

## Owner bug list (2026-11-07)
- [x] Logout kept the previous user's data in memory (the next account saw the old profile/home/circles): sign-out now restarts the app with a fresh provider scope after wiping tokens and local data.
- [x] Blank screen for the person who receives a Connect request: the Connect button in the Invites row inherited the theme's full-width minimum size (infinite width in a list row); fixed size.
- [x] Avatar colours: water sky blue, nutrition green, sleep purple; light tint over the whole body, darker fill from the feet up with a moving wave for 3 s after each change (static otherwise, to save battery; still with "reduce motion").
- [x] Rin AI on OpenAI GPT-5 mini (all three AI features), Rs 10 per user per month (V026, OQ-37). **Owner: put the real key in `OPENAI_API_KEY`; update the AI consent text / privacy policy to name OpenAI.**
- [ ] Phone notifications: postponed by the owner (needs a Firebase project; mobile `PushService` is still the disabled stub).
- [x] Intro slides rebuilt to Figma "Onboarding 1-3" (avatars with badges; profile tags -> goals; care circle + Rin; "1 of 3", dots, left-aligned text). The numbers on the slides are examples.
- [x] Reports: Download Report saves a copy to Downloads/NaraaCare on Android 10+ (MediaStore, no permission; MainActivity `savePdf` only accepts the app's own PDFs); iOS shows the app folder in Files; older Android keeps Share.
- [x] Monthly report picker: month + year only, from the month the account was created (GET /me `member_since`, V028; the database refuses earlier months).
- [x] Report content: per-section basic insights for every tier (rule-based, OQ-76), a nutrient bar chart, and for STAR "Advanced insights" = overall trend + 2-4 recommendations (AI, from averages and first-half/second-half trends only).
- [ ] Apple sign-in on Android: not a bug (OQ-67). Needs an Apple Developer account, a Service ID and an API callback route; button stays iOS-only until then.
- [x] Onboarding step 6: the three body types side by side as avatars (the user's figure drawn slimmer / broader until body-type art exists, OQ-56).
- [x] Onboarding step 7: no calorie / hydration targets; shows the avatar chosen in step 1.
- [x] Onboarding step 3: five goals only (OQ-75, V027).
- [x] Water avatar: press and swipe up / down (+/- 100 ml) now also works for a slow drag (48 px), not only a fast flick.
- [x] Pager dots under the avatar are tappable and open that avatar.
- [x] Share on each avatar (Figma: more, share, info): shares a picture of the figure and its card through the system share sheet.
- [x] Nutrition voice: recogniser errors now stop "listening" with a message; English (India) only when the phone has it. On the emulator the virtual microphone must be switched on (Extended controls > Microphone > "Virtual microphone uses host audio input").
- [ ] Tests to write: sign-out resets providers (widget test with two accounts); Invites row renders (widget); wave painter golden at 0 / 0.5 / 1; OpenAI model adapters with recorded responses (stream with tool calls, refusal, length); monthly cap (gate at the cap, reset on the 1st, drink estimate skipped at the cap, insights skipped below the reserve); pgTAP for V026-V028 (`700_ai` updated, `fn_get_profile.member_since`, report month before sign-up refused, retired goal refused); report builder basic insights per threshold; MediaStore save (instrumented test on Android 10+); intro slides / step 6 / step 7 widget tests; share button produces a PNG.

## Support and error-alert emails (2026-11-17)

- Done: user queries go to `support@naraacare.com` (`SUPPORT_INBOX_ADDRESS`, `SUPPORT_CONTACT_EMAIL`); unhandled API errors and failed worker jobs email `info@naraacare.com` (`ERROR_ALERT_EMAIL`, `app/integrations/error_alerts.py`).
- Owner: create both mailboxes on the naraacare.com domain; send from a naraacare.com address (`EMAIL_FROM_ADDRESS`) once a domain SMTP provider is set up.
- Tests to write: alert throttle (same error once per 15 min, hourly cap, skipped count in next email); alert body never contains the exception message, path values or emails; 500 handler calls the hook with the route template; worker middleware reports failed jobs; no email when `ERROR_ALERT_EMAIL` is empty.

## Owner alerts to info@naraacare.com (2026-11-17)

- Done: the 8 urgent alerts (OTP email, Google/Apple sign-in, AI credits/quota, Rin down/slow, paid without STAR, payment validation, report PDF, day jobs) in `app/integrations/ops_monitor.py`; worker health check `ops.health_check` every 5 min with `ops.fn_ops_health` (database). See [setup/owner-alerts.md](../setup/owner-alerts.md).
- Owner: set `AI_ACCOUNT_MONTHLY_BUDGET_INR` to the monthly limit set at platform.openai.com.
- Later: bounce spike needs the production email provider's bounce webhook (SMTP cannot see bounces). An outside uptime check (the worker cannot alert when the worker itself is down).
- Tests to write: RateWindow thresholds per alert; budget 80/95 levels; MonitoredEmail re-raises; auth OTP/OAuth counting; Rin ai_error + rin_reply calls; billing paid-without-STAR and payment_error points; report job and insights alerts; worker job-to-alert mapping and missed-run check; `ops.fn_ops_health` pgTAP (counts, rin-basic excluded, worker-only grant).

## Rin fallback chain (2026-11-11)
- [x] When OUR OpenAI account limits Rin (owner): gpt-5-mini -> on rate limit / overload / model error RIN_FALLBACK_MODEL (gpt-5-nano, own prices AI_FALLBACK_PRICE_*) -> when the account has no credits, hits its spending limit or the key is bad (every model refused), or both models fail: basic mode (app/domain/ai/basic_rin.py), free, from the user's own context: today's numbers, fixed tips, drink and meal proposal cards; no "AI paused" note, and each reply counts toward the user's monthly limit like a gpt-5-mini reply of the same size (usage row model rin-basic, tokens estimated at 4 characters each). Logs openai_account_unavailable for the owner. No key configured = basic mode instead of 503. The per-user Rs 10 cap is unchanged.
- [x] Checked against the dev database: no credits -> basic (lower model not called); rate limit -> lower model answers; both limited -> basic with a drink card.
- [ ] Verify gpt-5-nano prices on openai.com/api/pricing (defaults 0.05 / 0.005 / 0.40 USD per 1M tokens).
- [ ] Tests: failure_kind (quota / account / retry), chain order with FakeRinModel, basic_rin.answer cases (drinks incl. Hinglish, meals, status, tips, help).

## Notifications step 1: local reminders (2026-11-08)
- [x] flutter_local_notifications 22.3.3 (BSD-3) + timezone 0.11.2 (BSD-2); Android desugaring (desugar_jdk_libs 2.1.4, Apache-2.0), POST_NOTIFICATIONS + RECEIVE_BOOT_COMPLETED, the plugin receivers, status icon ic_stat_naraacare; iOS foreground delegate.
- [x] lib/features/notifications/data/local_reminders.dart: mirrors GET /me/reminders + preference toggles on the phone (fixed times daily; interval from wake to bedtime like ops.fn_due_reminders), in the profile timezone, inexact alarms. Synced at app start (LocalReminderSync on the tabs), after every change in Notification Settings, cleared on sign-out.
- [x] PushService: LocalPushService asks the OS permission (after the explainer); enablePush registers a device only when a push token exists (step 2).
- [x] Verified on the emulator: a water reminder at 18:07 was scheduled and shown ("Time for some water").
- [ ] Step 2 (needs the owner's Firebase project): firebase_messaging for server push (circles, connections, reports). Then avoid double reminders: when the device has a push token, either the server sends reminders or the phone does, not both (pick one; suggest phone for reminders, server for social).
- [ ] App icon: the launcher icon is still Flutter's default (shows on notifications); export from Figma "App Icon".
- [ ] Tests: reminderMinutes (times, interval, bedtime after midnight), sync respects toggles and permission (fake plugin), clear on sign-out.

## Owner bug list 4 (2026-11-08)
- [x] Rin scope: answers only about water/drinks, food/nutrition, sleep, supporting healthy habits and using NaraaCare (prompt rin-2026-11-08.1). Unmistakable coding/tech requests get a fixed reply on the server without a model call (guardrails.off_topic_reply; no AI cost).
- [x] Rin data from the backend: new tool get_my_data -> ai.fn_rin_lookup (own day totals, 1-90 day averages, a day's meals with catalogue food names; last 90 days; same gate and data minimisation as fn_rin_context).
- [x] Rin chats already stored: ai.conversation + ai.message (prompt saved before the reply, reply saved after; failed replies are not stored).
- [ ] Apple sign-in on Android: hidden by design (social_sign_in.dart appleAvailable = iOS only, OQ-67). Needs an Apple Developer account (Service ID, key), the API callback route for APPLE_REDIRECT_URI and the Android web flow; Apple config values in .env are still placeholders.
- [ ] Tests to write: off_topic_reply true/false cases, get_my_data tool handling (valid/invalid), pgTAP for ai.fn_rin_lookup (gate, 90-day limit, other user).

## Owner bug list 3 (2026-11-08)
- [ ] Rin AI "resting": the OpenAI account has no credits (429 insufficient_quota / credit_balance_exhausted). **Owner: add credits at platform.openai.com billing.** No code change needed.
- [x] Member avatar screen: the avatar fills the page down to the dots.
- [x] Onboarding 3 and Welcome rebuilt to Figma (world map + cards; serif tagline). **The map image (`assets/illustrations/world_care.png`) is a placeholder cropped from a screenshot: export Figma layer "image 78" (node 1629:3697) at 3x and replace the file** (Figma MCP call limit reached).
- [x] Splash: owner's Lottie animation (`assets/brand/splash.json`, package `lottie` 3.8.2, MIT) on every start; the router holds the splash until it ends while the session check runs; Android 12+ system splash is plain white.
- [x] Avatar wave fill lighter (0.42 instead of 0.85).
- [x] PDF report redesigned to the owner's Figma report: cover (goal achievement per section, highlights), Hydration / Nutrition / Sleep pages (overview tiles, daily bars, nutrient meters vs targets, top meals, foods logged, sleep quality ring, insights), Advanced Insights (trend vs the previous period per section, overall trend, recommendations; rule-based fallback when the AI call is skipped). New `ops.fn_report_extras`. Goal achievement: nutrition = days within +/-10 % of the calorie allowance; sleep = nights at or above the goal (OQ-76).
- [ ] Local builds: run Flutter through the short path `C:/Users/SANKAL~1/flutter/bin/flutter.bat` (the space in the user path breaks the objective_c build hook). `flutter test` then starts but hangs (likely `pumpAndSettle` with the always-moving wave and the splash animation): the test harness needs `disableAnimations: true`.
- [ ] Tests to write: `fn_report_extras` (pgTAP), builder pages per section / no data / fallback advanced, splash hold in `authRedirect`.

## Owner bug list 2 (2026-11-08)
- [x] Monthly report picker: choose the year first, then the month (only months from sign-up to now).
- [x] Onboarding step 6: body types in a horizontal carousel of large cards.
- [x] Water avatar fill, ring and caption = share of today's goal drunk (starts at 0 % each day); the body-water tank level stays in the info sheet (OQ-17 changed).
- [x] Avatar wave always moves (still only with the system "remove animations" setting).
- [x] Share stays inside NaraaCare (V029, `POST /avatar-shares`, `social.pr_share_avatar`): own circles get a 'shared' card in Recent Updates, connections get an `avatar_shared` notification. The database builds the snapshot (numbers only); strangers cannot be reached. Fixed in passing: cards shared into one circle never show in another (`fn_feed_rows`).
- [x] Welcome "Get Started" opens the three intro slides, then Sign Up (first install: Splash -> slides -> Sign Up, as in Figma).
- [x] Active Streak with no data: `fn_streak.broken_yesterday` was NULL (app failed to parse) -> FALSE; Download Report disabled until a day is logged; the database refuses a report for a period with no data (422 REPORT_NO_DATA).
- [ ] Tests to write: pgTAP for `pr_share_avatar` (member/connection/blocked/limits, sleep STAR, feed isolation per circle), `fn_streak` with no data, REPORT_NO_DATA; widget tests for the share sheet, year/month picker, step 6 carousel, intro from Welcome. `flutter test` fails locally because the Windows user path has a space (objective_c native-asset hook) - run tests from a path without spaces or in CI.

## Session 16: Security hardening and testing (in progress)
Decisions (2026-11-05): write the S16 security suite AND every deferred S09-S15 test list; install scanners as needed, checking licences (commercial product); build Play Integrity / App Attest in soft-fail mode.
- [x] Backend security suite (tests/security, all green against the scratch database): `authz_matrix.yaml` + `test_authz_matrix.py` (141 routes classified: public / user / staff / STAR feature; **product review needed**), `test_idor_all_ids.py` (every id route with another user's real ids -> 404, owner control, data unchanged), `test_jwt_attacks.py` (18 forgeries, kid/jku/jwk headers, token only from the header, tampered tier, key-rotation drill with kid overlap), `test_rate_limits.py`, `test_enumeration.py`, `test_webhooks_forgery.py` + `tests/stores.py` (test Apple PKI, Google OIDC signer, fake Play), `test_receipt_reuse.py`, `test_uploads.py`, `test_sse_ws_limits.py`, `test_mass_assignment.py`, `test_injection_lists.py` (new lists `sqli.txt` 64, `path_traversal.txt` 41, `csv_injection.txt` 26; xss.txt parity across the three repos), `test_prompt_injection.py` + `payloads/prompt_injection.yaml` (20 red-team cases against a worst-case model) and `tools/rin_redteam.py` (staging run with a real model, results reviewed by a person).
- [x] Fixes from the suite: (1) password change now ends the other devices' access tokens at once (was: up to 15 min); (2) the documented global limit 300/min/user was never applied, now enforced in `current_user`; `calculations/preview` and cancel-deletion got the `writes` limit; (3) lockout revealed registered emails (unknown emails never locked): new `auth.fn_unknown_email_locked_until`, unknown emails now lock exactly like accounts, and no lockout email goes to an address without an account; (4) receipt sharing failed with 422 and logged nothing because `purchase_token_reuse` was missing from `audit.security_event`'s CHECK: migration **V025** (now 409 PURCHASE_TOKEN_IN_USE + security event); (5) open chat WebSockets stayed connected after logout / logout-all / password change / reset / deletion: sockets are tied to their session and closed on revocation; (6) CSV export guard also catches formulas after leading whitespace; (7) **Pillow 12.3.0 -> 13.0.0** (39 known CVEs; it decodes untrusted screenshots).
- [x] Scanners: Semgrep CE 1.183 (LGPL-2.1, dev-only; our rules + the p/python and p/owasp-top-ten packs CI already uses, Semgrep Rules License permits internal scanning): 7 new rules (eval/exec, unsafe deserialisation, shell, TLS verify off, jwt without algorithms, insecure random, HTML responses) with fixtures; 0 findings. Bandit: 0 (3 false positives marked). pip-audit: no known vulnerabilities. Schemathesis 4.33 (MIT) installed, not run yet.
- [x] Database: pgTAP 20/20, no drift, local scratch database at V025. **Owner:** run Flyway migrate on your local database (V025).
- [ ] Next: DB `950_security_payloads_all_columns`, `960_privileges_audit` and the deferred pgTAP files; backend deferred S09-S15 tests and the old "tests to update"; Schemathesis run; Play Integrity / App Attest soft-fail; mobile (18 failing tests from S08, security tests, widget tests, MASVS checklist, release checks); ZAP / MobSF / mitmproxy (need Java / a release APK); input inventory CSV; hosting hardening, runbooks, pen-test scope.
- [ ] Noted, not changed: Rin streams lightly cleaned deltas (angle brackets and markdown removed) and the cleaned full text arrives in `done`; a `javascript:` string can appear in a delta, harmless because the app renders plain text only (keep it that way). Chat messages refuse underscores (allow-list); confirm that is intended.
- [ ] Tests to write later: the session's own security test plan (fast subset per PR, full sweep nightly), plus every deferred "Tests to write later" item from Sessions 09-15 not done by then.

## Session 17: Performance, release, store (not started)
- [ ] Whole session. Carried in: hosting provider choice (OQ-45), Android release signing, OQ-46 (Sentry data residency).
- [x] Decisions (2026-11-05, owner): finish Session 16 before starting S17; hosting provider chosen later by the owner (OQ-45 stays open); load tests with k6 (AGPL-3.0, internal use only, never modified or shipped); **no crash reporting at launch** (OQ-46): store crash reports (Play Console, App Store Connect) and server logs only, Sentry may be added later.
- [ ] Tests to write later: k6 scenarios with thresholds as CI pass/fail; plan tests; release config tests; post-deploy smoke tests (synthetic canary); store sandbox purchase on production-signed builds (license testers / TestFlight).

## Mobile fixes: logout, app icon, no DEV ribbon (2026-11-20)

Tests to write:
- `AuthController.signOut`: when `wipeLocalData` throws, status still becomes `signedOut` and `onSignedOut` runs.
- `authControllerProvider` wipe: when reminders `clear()` throws, `wipeLocalUserData` still runs.
- Release APK check in CI: `aapt2 dump resources` lists `drawable/ic_stat_naraacare` (kept by `res/raw/keep.xml`).
- Fix existing failures, not caused by this change: all `test/app_smoke_test.dart` tests (`pumpAndSettle` times out) and 7 tests in `test/core/routing/router_test.dart`.

## AI data isolation tests (2026-11-22)

Checked live on the dev database (2026-11-22): acting as user B, every Rin read of user A is refused
(`fn_rin_context`, `fn_rin_lookup`, `fn_usage_month`, `fn_history`, `fn_conversations`), and
`fn_history(B, <A's chat>)` returns no rows. Add these to `naraacare-database/tests/700_ai.sql`
(today only fn_messages / write / delete of another user's chat are tested):
- `ai.fn_rin_context(A)` and `ai.fn_rin_lookup(A, ...)` as actor B raise 42501.
- `ai.fn_history(B, <A's conversation>)` returns 0 rows.
- `ai.fn_pending_action` / `ai.pr_resolve_pending_action` on A's action as B raise 42501.
- `ai.fn_usage_month(A)` as B raises 42501.
- Backend: a `get_my_data` tool call can only ever read the token's user (the tool has no user parameter).

## Home avatar UI: screen scaling, side badge, cleaner page (2026-11-24)

Tests to write:
- `screenScaleFor`: 390 dp = 1.0; 320 dp clamps to 0.85; 800 dp clamps to 1.3; text part caps at 1.15.
- App text scale = user text size (max 130 %) x screen scale (`app.dart`).
- `NcAvatarFigure` with a fixed `height` scales with the screen; inside `NcAvatarStage` it does not.
- `AvatarUpdates.post` shows the badge on the matching tracker only and clears it after 4 s.
- Water swipe, add drink, new meal and new sleep show the side badge, not a toast; editing sleep keeps the toast.
- Over-hydration caution shows as the red side badge when no update is showing.
- Home shows no text between the avatar and the button.
- Visual check of the badge position on a 360 dp and a 412 dp phone.
