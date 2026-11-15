# Session 17 — Performance Testing, Release Builds, Store Readiness

## Goal and scope
Prove performance at target scale, optimise hot paths, choose the hosting provider and set up production, produce signed/obfuscated release builds, complete store listings and compliance forms, and run a staged launch with monitoring.

**In:** k6 load tests, DB plan tests, app performance profiling, hosting provider selection (vendor-neutral checklist, doc 11 §2) + storage adapter + deploy scripts, release pipelines, store metadata, launch checklist.
**Out:** post-launch features.

## Prerequisites
S16 complete; legal documents published (OQ-47); food DB licensing cleared (OQ-42); nutritionist sign-off on calculation constants (OQ-12); pricing set in stores (OQ-06).

## Files to create / modify
```
naraacare-backend/tests/performance/k6/{scenario_mixed.js, scenario_spike.js, scenario_soak.js, thresholds.json}
naraacare-backend/tools/seed_synthetic.py (100k users × 90 days)
naraacare-database/tests/980_plan_tests.sql      # EXPLAIN (FORMAT JSON) assertions: index-only scans, partition pruning
naraacare-database/tools/verify_restore.sql
naraacare-backend/deploy/*                       # scripted staging/prod setup on the chosen provider (doc 11 §2); no containers
naraacare-backend/app/integrations/storage_<provider>.py   # object-storage adapter + settings guard (filesystem refused outside dev)
naraacare-mobile/fastlane/{Fastfile, Appfile, metadata/android/*, metadata/ios/*}
naraacare-mobile/android/app/build.gradle (release signing via CI secrets, minify, shrinkResources)
naraacare-mobile/store/{data_safety_answers.md, app_privacy_labels.md, health_declarations.md, screenshots/}
docs/launch-checklist.md (in docs repo)
```

## Step-by-step tasks
1. **Load tests** (doc 10 §5): mixed 2,000 VUs for 30 min, spike ×3 for 5 min, soak 4 h; record p95 per route, error rate, DB CPU, PgBouncer waits, Redis latency. Fix regressions (indexes, query shapes, caching of `/reference/bootstrap` and entitlements, connection pool sizes).
2. **DB**: plan tests green; autovacuum settings per partition; `pg_stat_statements` top-10 review; replica routing for read-only endpoints; partition premake verified 3 months ahead.
3. **App performance**: cold start ≤ 2.5 s on a mid-range Android (deferred init of non-critical services, image asset optimisation WebP, Lottie sizes), 60 fps in the avatar carousel (DevTools timeline), APK/IPA size budget (≤ 40 MB download), memory leak checks.
4. **Prod hosting**: pick the provider (Indian region; managed PostgreSQL 18, managed Redis, private object storage, secret manager, load balancer + firewall; DPA signed), run the setup scripts; secrets (incl. the field-encryption master key) populated in the secret manager; DNS, TLS certificate, firewall, SMTP provider production access, Pub/Sub RTDN + ASSN production endpoints, FCM prod project, Anthropic prod workspace with spend limit; backups + cross-region copy; alarms and dashboards; synthetic canary.
5. **Restore drill** in prod-like staging; record RTO/RPO.
6. **Release builds**: `flutter build appbundle --flavor prod -t lib/main_prod.dart --release --obfuscate --split-debug-info=build/symbols --dart-define-from-file=env/prod.env`; `flutter build ipa` likewise; upload symbols to Sentry; verify release config tests (no debug logging, pins present, HTTPS-only).
7. **Store readiness**:
   - Google Play: Data safety form (health & fitness data, personal info; encrypted in transit; deletion available), Health apps declaration, target API level current, account deletion URL + in-app path, subscriptions configured with base plans/offers, content rating, privacy policy URL, App Links verified.
   - App Store: App Privacy labels (Health & Fitness, Contact Info: email; linked to user; not used for tracking), in-app account deletion (guideline 5.1.1(v)), Sign in with Apple present alongside Google (4.8), subscription group + review screenshots, medical disclaimer in description and app (1.4.1), Universal Links verified, export compliance (standard encryption only).
   - Screenshots and descriptions for both stores (English; Hindi later).
8. **Staged rollout**: internal testing → closed beta (100 users) → Play staged 5/20/50/100 % and App Store phased release; monitor crash-free sessions, 5xx, latency, store notification lag, LLM spend; rollback plan (halt rollout, server feature flags, `RIN_ENABLED=false`).
9. **Launch checklist sign-off**: OQ decisions recorded, legal sign-off, security sign-off (S16), nutritionist sign-off, product sign-off.

## DB objects / API endpoints / Screens
No new ones (performance fixes only). Store screenshots from final Figma-matching builds.

## Security checks
Release hardening (SEC-5.3), prod config guards (docs disabled, TLS verify-full, no local keys), secrets only in the secret manager, store compliance for privacy/deletion, monitoring + breach runbook live.

## Input-validation checklist
- [ ] Final regression run of the full 3-layer payload suite on the release candidate builds and the prod-like stack.
- [ ] Input inventory (S16) re-generated; no new gaps.

## Tests to write
k6 scenarios with thresholds as CI pass/fail; plan tests; release config tests; smoke tests post-deploy (synthetic canary); store sandbox purchase on production-signed builds (license testers / TestFlight).

## Acceptance criteria / Definition of done
- [ ] All SLOs in doc 10 §5 met at 2,000 VUs with error rate < 0.1 %.
- [ ] Restore drill achieved RPO ≤ 5 min, RTO ≤ 2 h.
- [ ] Signed, obfuscated builds pass MobSF and release-config tests; symbols uploaded.
- [ ] Both stores approve the app (production track/phased release started).
- [ ] Dashboards and alarms live; on-call rota and runbooks in place.
- [ ] Launch checklist fully signed.

## Estimated effort
8–10 developer-days + store review time (allow 1–2 weeks calendar).
