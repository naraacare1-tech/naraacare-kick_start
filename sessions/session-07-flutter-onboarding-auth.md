# Session 07 — Flutter: Welcome, Auth and Onboarding Screens

## Goal and scope
Build every launch, authentication and onboarding screen from Figma and connect them to the S05 API: sign-up, OTP, sign-in, Google/Apple, forgot/reset password, 6-step onboarding with resume, result page, consent, save/generating/success, username sheet, Edit Profile, Username, Account (change password). Home shell with the 4-tab bottom navigation and placeholder avatars.

**In:** `features/auth`, `features/onboarding`, `features/settings` (profile/username/account parts), consent UI, legal screens (rendered as native text from fetched versions or opened in the external browser — not WebView).
**Out:** avatar logic (S08–S10).

## Prerequisites
S05, S06. OQ-25, OQ-26, OQ-27, OQ-28, OQ-30, OQ-33 (condition list), OQ-56 (avatar assets) decided or defaults accepted.

## Files to create (naraacare-mobile)
```
lib/features/auth/data/{auth_api.dart, auth_repository_impl.dart, dto/*.dart}
lib/features/auth/domain/{entities/session.dart, auth_repository.dart, use_cases/*.dart}
lib/features/auth/presentation/screens/{welcome,sign_up,verify_email,email_verified,sign_in,forgot_password,reset_code,set_new_password,password_changed}_screen.dart
lib/features/auth/presentation/providers/*.dart  widgets/{social_buttons,password_rules}.dart
lib/features/onboarding/... screens/{intro,step1_identity,step2_height,step3_weight_goal,step4_target_conditions,step5_age_activity,step6_body_type,result,generating,saved}_screen.dart
lib/features/onboarding/presentation/widgets/{height_ruler,weight_input,goal_dropdown,condition_search,activity_options,body_type_carousel,wave_progress}.dart
lib/features/settings/presentation/screens/{settings,edit_profile,username,account,change_password}_screen.dart
lib/features/privacy/presentation/consent_sheet.dart
lib/features/home/presentation/home_shell.dart greeting_header.dart
assets/avatars/ (from design; WebP), assets/fonts/Manrope/*
test/features/auth/** test/features/onboarding/** integration_test/onboarding_flow_test.dart
```

## Step-by-step tasks
0. Flow follows the MVP document (doc 02 §2.0): Splash → intro slides A1a (first install only, Skip) → Welcome → Get Started → Sign Up → Check Your Email → Email Verified → onboarding; Welcome → Sign In → Home. Only visible frames on the Figma App Design page are built; hidden ones (Referral, Mobile Verification, Full Name/Mobile fields) are not.
1. Welcome (A2), Sign Up (A3: email, password, confirm, terms; no Full Name, OQ-65) with states: hidden/shown password, email already registered, password mismatch, terms required; social buttons with error banners (A11).
2. Verify Email (A4): `NcOtpInput` (6 boxes, paste support, `oneTimeCode` autofill), resend countdown 00:30, "New code sent" toast, wrong-code state with attempts left, expiry state.
3. Sign In (A6) with generic error; lockout message with retry time; Forgot Password (A7) → Check Your Email with 6 code boxes (A8; copy says "code", not "link", OQ-64) → Set New Password (A9) with live rules checklist (8 chars, uppercase, number) → Password Changed (A10).
4. Google (`google_sign_in` 7.2, server client ID) and Apple (`sign_in_with_apple` 8.2, nonce SHA-256) → backend; handle `LINK_REQUIRED` with a password prompt.
5. Onboarding O0–O7: wave progress bar, Go Back on every step, unit toggles (ft/in ↔ cm, kg ↔ lb with conversion to metric before sending), goal dropdown populated from `/me/goal-options`, healthy-range hint + below/above warning, condition search over `ref.medical_condition` (local filter, chips), age 18–100, 4 activity options, body-type carousel with the chosen name in info text, result summary (Edit Details / Save my avatar), consent sheet (terms/privacy/health_data required, AI optional), generating → saved → Home.
6. Resume: on launch, `GET /me/onboarding` routes to the saved step.
7. Home shell: greeting by local time (Morning 05–12, Afternoon 12–17, Evening 17–05), 4 tabs, avatar carousel placeholders.
8. Username sheet (H2/C2) with debounced availability check and the "once every 3 months" note.
9. Settings: Edit Profile (ST2; recalculates today), Username (ST3), Account (ST4: change password; delete account entry added in S15), Log Out.
10. Apply `ScreenGuard` (FLAG_SECURE) on A3–A10, ST4.

## DB objects
None.

## API endpoints used
All S05 endpoints.

## Screens (Figma frames)
`Splash`, `Onboarding 1 - Meet your health avatars`, `Onboarding 2 - Goals made for your body`, `Onboarding 3 - Care for each other`, `Welcome`, `Sign Up` (+ Filled/Password Hidden, Password Shown, Error State/Email already registered, Password Mismatch), `Email Verification` (+ -1, -2, Resent code, Wrong OTP), `Email Verified`, `Sign In` (+ Error State), `Forgot Password` (+ Email, Error State), `Forgot Password/Reset Password/Verification`, `Reset Password` (+ -1), `Password Changed`, `After sign in/Onboarding`, `Onboarding 1` (Default/Typing/Filled), `Onboarding 2` (cm/ft), `Onboarding 3`, `Onboarding 4`, `Onboarding 5`, `Onboarding 6`, `Onboarding 6-1`, `Generating your health profile…`, `Final page`, Profile Username sheet, `Settings`, `Edit Profile`, `Username`, `Account`.

## Security checks
SEC-5.1 (tokens only in secure storage), SEC-5.5 (FLAG_SECURE on auth screens), SEC-5.10 (password field flags), SEC-1.4 (nonce for Apple/Google), SEC-7.1 (consent captured with policy versions), no input echoed in errors, OQ-26 copy applied.

## Input-validation checklist
| Field | Validator | maxLength | Backend type |
|---|---|---|---|
| Email | `email()` | 254 | SafeEmail |
| Password / Confirm / New / Current | `password()` / `confirmPassword()` / `passwordLogin()` | 128 | SafePassword |
| OTP (6 boxes) | `otp()` digits-only formatter | 6 | SafeOtp |
| Full name | `name()` | 100 | SafeName |
| Height (cm / ft-in) | `decimal(120,230,1)` / pickers | 5 | condecimal |
| Weight / target | `decimal(30,250,2)` (lb converted) | 6 | condecimal |
| Age | `integer(18,100)` digits only | 3 | conint |
| Condition search | `search()` (local only) | 64 | — (codes sent) |
| Username | `username()` lower-case formatter | 30 | SafeUsername |
- [ ] Each field above has a widget test with the payload list.

## Tests to write
Widget tests per screen state (golden for main states); validator wiring tests; unit conversion tests (5'8" = 172.7 cm; 120 lb = 54.43 kg); onboarding resume test; integration test of sign-up → onboarding → Home against a mocked API; patrol E2E against staging (nightly): sign-up with a test inbox, Google sign-in (test account), Apple (iOS only).

## Acceptance criteria / Definition of done
- [ ] Every frame listed renders pixel-close to Figma on iPhone 390×844 and Android 412×917 (golden tests reviewed by design).
- [ ] All error states from DOC §2.4 behave as specified (with OQ-26/27/28 decisions).
- [ ] Quitting mid-onboarding resumes at the same step.
- [ ] Result page numbers come from `/calculations/preview` (no local maths besides unit conversion).
- [ ] Consent records exist after completion (verified via API).
- [ ] No raw text fields; all validators + maxLength present; payload widget tests green.

## Estimated effort
8 developer-days (mobile) + 1 day design QA.

## Implementation status (2026-10-31)

Verified locally with Flutter 3.47.7 (Windows). Nothing is committed yet.

| Acceptance criterion | Status |
|---|---|
| Every listed frame renders pixel-close to Figma (golden tests reviewed by design) | ⚠️ **Open.** The Figma Starter-plan MCP limit allowed one screenshot, and the illustration and avatar exports were refused. Screens follow the App Design page structure, its text layers and doc 02, with the S06 tokens; icons stand in for the illustration and avatar art (OQ-56). Goldens wait for that review (and a Linux-rendered baseline, see S06). |
| DOC section 2.4 error states (OQ-26/27/28) | ✅ widget tests per state: email registered, password mismatch, weak password, terms required, wrong code with attempts left, expired, locked, resend countdown + "New code sent", wrong credentials (password cleared), lockout minutes, unverified account → code, reused password, provider unreachable / refused, `LINK_REQUIRED` link sheet |
| Quitting mid-onboarding resumes at the same step | ✅ resume tests: last saved 0 → step 1, 3 → step 4, 6 → result, completed → Home; offline shows a retry |
| Result numbers come from `/calculations/preview` | ✅ test reads kcal and water from the preview response; the app does unit conversion only (5'8" → 172.7 cm and 120 lb → 54.43 kg are tested end to end) |
| Consent records exist after completion | ✅ (app side) the complete call carries terms, privacy and health data (required, gated) plus AI (optional, off) with the policy versions from `/reference/policies`. Checking the stored records against a running API is part of the staging E2E (S16) |
| No raw text fields; validators + maxLength; payload widget tests | ✅ source rule still green; payload sweep over every S07 text field (sign up, sign in, forgot, new password, code, name, weight, target, condition search, age, username, Edit Profile, change password): nothing unsafe reaches the API, formatter fields send only digits/decimals/`[a-z0-9._]`, nothing echoed |
| Quality gates | ✅ 217 tests (85 new for S07 + the full first-run flow), `flutter analyze --fatal-infos`, `dart format` clean |

**Built** (`naraacare-mobile/lib/features/`): auth (A2-A11, Google/Apple with SHA-256 nonces, `LINK_REQUIRED`), onboarding (A1a, O0-O7 with resume, unit toggles, BMI goal guardrails, local condition search, consent, completion), home (greeting, avatar placeholders, username sheet H2), settings (ST1-ST4, Log Out with server revocation, legal links in the browser), `profile/data` (`/me` client, reference payload cached in the encrypted DB). `ScreenGuard` on the auth screens and Account.

**Tests:** `test/features/auth/` (Welcome, Sign Up, code, Sign In, reset, social), `test/features/onboarding/` (conversion, resume, each step, result/consent/completion), `test/features/settings/` (greeting, username sheet, settings, Edit Profile, username, change password, log out), `test/features/payload_fields_test.dart`, `test/features/sign_up_to_home_flow_test.dart`. The same flow runs on a device as `integration_test/onboarding_flow_test.dart` (`flutter test integration_test --flavor dev`). Patrol E2E against staging (real inbox, Google, Apple) needs staging and test accounts: S16.

**Bugs the tests found and fixed:** intro slides overflowed on short screens; "Already have an account? Sign In" could not wrap; buttons kept spinning behind the link and consent sheets; the generating screen read localisations during `initState`; the empty condition search box failed form validation (blocked Edit Profile and step 4); Home could crash when left before `/me` answered.

**Open:** Figma pixel review and assets (above); Apple on Android (OQ-67); avatar code at step 1 (OQ-68, backend change suggested); the forgot-password "no account" state (OQ-69, copy sign-off). Settings entries for notifications (S13), subscriptions (S14), referrals (S11), help and delete account (S15) are shown disabled.
