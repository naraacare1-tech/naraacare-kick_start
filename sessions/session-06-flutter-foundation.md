# Session 06 — Flutter: Design Tokens, Routing, Network Layer, Secure Storage, Shared Input Validators, Offline DB

## Goal and scope
Build the mobile chassis: Figma design tokens and theme, shared widgets, go_router with guards, dio client (auth refresh, request id, error mapping, certificate pinning), secure storage, SQLCipher drift DB + outbox sync engine skeleton, localisation, root warning, screen privacy, and the **shared input validators** with `NcTextField`.

**In:** `lib/core/*`, `lib/shared/*`, test harness, payload widget tests.
**Out:** feature screens (S07+).

## Prerequisites
S01. Figma tokens confirmed (OQ-01) or sampled tokens accepted temporarily; OQ-50, OQ-57 defaults.

## Files to create (naraacare-mobile)
```
lib/core/config/app_config.dart flavor.dart                 # String.fromEnvironment keys (doc 08 §4); asserts
lib/core/theme/tokens.dart                                   # colours, spacing, radius, sizes (doc 02 §1)
lib/core/theme/typography.dart app_theme.dart                # Manrope (bundled font assets, OFL licence in Licenses)
lib/core/routing/app_router.dart routes.dart guards.dart     # auth / onboarding / username / tier guards
lib/core/network/dio_client.dart pinning.dart
lib/core/network/interceptors/{auth_refresh,request_id,retry,error_mapper,connectivity}.dart
lib/core/errors/failure.dart api_error.dart error_messages.dart
lib/core/security/input_validators.dart                      # doc 07 §4.3; mirrors backend rules
lib/core/security/reject_patterns.dart                       # R1–R9 (doc 07 §4.2)
lib/core/security/secure_storage.dart                        # tokens, DB key, installation id
lib/core/security/root_check.dart screen_guard.dart deep_link_validator.dart biometric_gate.dart
lib/core/storage/app_database.dart tables/*.dart daos/*.dart  # drift + SQLCipher; outbox table
lib/core/sync/outbox.dart sync_engine.dart conflict_resolver.dart
lib/core/l10n/app_en.arb app_hi.arb (stub)  l10n.yaml
lib/core/utils/units.dart clock.dart logger.dart              # logger no-op in release
lib/shared/widgets/nc_text_field.dart nc_button.dart nc_chip.dart nc_otp_input.dart nc_wheel_picker.dart
lib/shared/widgets/nc_bottom_sheet.dart nc_error_banner.dart nc_toast.dart nc_star_badge.dart nc_upsell_sheet.dart
lib/shared/widgets/nc_bottom_nav.dart nc_avatar_card.dart nc_empty_state.dart nc_offline_banner.dart
lib/shared/widgets/app_switcher_privacy.dart
android/app/src/main/res/xml/network_security_config.xml       # cleartext off; no user CAs in release
android/app/src/main/AndroidManifest.xml                       # allowBackup=false, permissions minimal
ios/Runner/Info.plist                                          # ATS default, usage descriptions (camera, mic, Face ID)
test/core/security/input_validators_test.dart                  # all payloads rejected; valid multilingual accepted
test/core/security/no_raw_textfield_test.dart                  # scans lib/ for TextField/TextFormField outside nc_text_field.dart
test/core/network/auth_refresh_interceptor_test.dart pinning_test.dart
test/core/sync/outbox_test.dart
test/shared/widgets/golden/*_test.dart
test/security/payloads/xss.txt
```

## Step-by-step tasks
1. Tokens from doc 02 §1 into `tokens.dart` (no hex literals elsewhere; custom lint `avoid_hardcoded_colors`).
2. Theme: Material 3 with custom `ThemeExtension` for NaraaCare tokens; text scale up to 1.3 tested.
3. `NcTextField({required validator, required maxLength, inputFormatters, keyboardType, …})`; error text from `error_messages.dart`; no echo of input; `enableSuggestions:false` for secure fields.
4. `InputValidators` (pure Dart, unit-tested): `name, username, email, password, passwordLogin, confirmPassword, otp, integer, decimal, shortText, freeText, chatMessage, search, usernameSearch, barcodeOrSearch`. Normalisation: NFKC (`unorm_dart`, pin in S06), reject patterns, allow-lists, lengths.
5. dio: base URL from config; interceptors — request id (UUIDv7), auth header, single-flight refresh on 401 `TOKEN_EXPIRED` (mutex), retry idempotent GETs with backoff, error mapper → `ApiError(code, fields)`. Pinning via `IOHttpClientAdapter(validateCertificate: (cert, host, port) => spkiPinned(cert))` + standard validation; pins from `CERT_PINS`.
6. Secure storage wrapper (Keychain accessibility `first_unlock_this_device`; Android encrypted shared prefs backed by Keystore).
7. drift DB with SQLCipher (key generated on first launch → secure storage); tables: `outbox`, `cached_status`, `local_entries` (hydration/meal/workout/sleep), `reference_cache`.
8. Outbox: enqueue(op, payload, client_entry_id); `SyncEngine` flushes FIFO per resource when online/foreground; handles 2xx/409/403/422 per doc 03 §3.1; pulls `/sync/changes`.
9. go_router following the document flow (doc 02 §2.0): splash → (first install: intro slides, `intro_seen` flag in secure prefs) → welcome when signed out; signed in → (refresh) → onboarding guard (resume step) → home shell with 4 tabs (`StatefulShellRoute`); deep links `/invite/:code`, `/circle/:token` validated.
10. Root check (warn banner), app-switcher privacy overlay (all screens), `ScreenGuard` widget enabling FLAG_SECURE/secure overlay on wrapped screens.
11. Biometric gate on resume (setting off by default).
12. l10n setup; all strings via ARB.

## DB objects / API endpoints
None new (uses `/auth/token/refresh`, `/reference/bootstrap`).

## Screens (Figma)
Foundations page components (buttons, text field states, dialogs, chips, bottom nav, sheets). A1 `Splash` (token check + bootstrap). Only visible frames on the Figma App Design page are implemented (doc 02 §0 rule).

## Security checks
SEC-5.1 secure storage · SEC-5.2 HTTPS-only + pinning + cleartext blocked · SEC-5.3 logger no-op in release · SEC-5.4 root warn · SEC-5.5 screen privacy · SEC-5.6 biometric gate · SEC-5.8 deep link validation · SEC-5.9 encrypted local DB · SEC-2 Layer 1.

## Input-validation checklist
- [ ] `InputValidators` implements every function listed; rules mirror backend Safe* types (shared test vectors file `test/core/security/vectors.json` copied from backend).
- [ ] `NcTextField` requires a validator and `maxLength`; raw TextField usage fails `no_raw_textfield_test`.
- [ ] Numeric fields use `FilteringTextInputFormatter`.
- [ ] Payload list v1.0.0 rejected by every text validator (widget tests).

## Tests to write
Validator unit tests (payloads + valid vectors); `NcTextField` widget tests (error shown, no echo); refresh interceptor (concurrent 401s → one refresh); pinning test (bad pin → connection refused); outbox (offline queue, replay idempotency, 409 server-wins); router guards; golden tests for shared widgets (iOS/Android sizes); release-mode logger no-op test.

## Acceptance criteria / Definition of done
- [ ] Tokens match Figma (or flagged as sampled with OQ-01 open); no hard-coded colours/sizes in widgets.
- [ ] App boots per flavor, performs silent refresh, routes correctly by auth/onboarding state.
- [ ] Pinning blocks a mitmproxy-intercepted connection in a staging build.
- [ ] Local DB file is encrypted (opening it without the key fails).
- [ ] All validator and payload tests green; lint forbids raw text fields.

## Estimated effort
6 developer-days.

## Implementation status (2026-10-31)

Verified locally with Flutter 3.47.7 on Windows. Nothing is committed yet.

| Acceptance criterion | Status |
|---|---|
| Tokens match Figma, no hard-coded colours/sizes in widgets | ✅ sampled from the App Design page (OQ-01 stays open for an official token export); a source-rule test fails on any `Color(0x…)`/`Colors.x` outside `tokens.dart` |
| App boots per flavor, silent refresh, routes by auth/onboarding state | ✅ router tests: first install → intro, signed out → Welcome, stored session → refresh → Home, refused refresh → Welcome, offline keeps the session, onboarding guard, deep links validated |
| Pinning blocks an intercepted connection | ✅ against a local TLS server: right pin connects, wrong pin → `CERTIFICATE`. mitmproxy check on a staging build still to do (needs staging) |
| Local DB file is encrypted | ✅ SQLCipher via the `sqlite3` build hook; the file is unreadable without/with a wrong key |
| Validators, payloads, no raw text fields | ✅ 538 payloads rejected by all 14 text validators; shared vectors file with the backend; `NcTextField` widget tests (no echo, secret-field flags, formatters); source rules (raw text fields, print/debugPrint, colours, WebView packages, invisible/bidi characters) |
| Quality gates | ✅ 132 tests, `flutter analyze --fatal-infos` clean, `dart format` clean; CI also checks that generated l10n/drift code is up to date |

Decisions and deviations (docs 00, 03, 04, 07, 08 updated):
- **Leaf SPKI pinning** instead of intermediate pins (`dart:io` only exposes the leaf certificate), OQ-66 opened for ops sign-off.
- **SQLCipher** through `sqlite3`'s build hook (`source: sqlcipher`); `sqlcipher_flutter_libs` is end-of-life. The app refuses to open an unencrypted database.
- **409 `VERSION_CONFLICT`** carries the server copy in `error.current` (doc 04); the app takes it and flags the entry.
- **Retries** run on a separate dio without the auth interceptor, so a failing retry can never deadlock the refresh queue; only GETs are retried.
- **Golden tests deferred** to design QA (S07): font rendering differs between Windows and the Linux CI runners.
- **Android:** `MainActivity` is a `FlutterFragmentActivity` (needed by `local_auth`); `INTERNET` and `USE_BIOMETRIC` only. Debug builds alone allow cleartext to `10.0.2.2`/`localhost`.
- **iOS:** ATS default (no exceptions); Face ID, camera and microphone usage descriptions.
