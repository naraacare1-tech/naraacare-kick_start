# Session 05 — Backend + DB: Authentication and User Profile

## Goal and scope
Implement sign-up with email OTP, login, Google/Apple sign-in, refresh rotation, logout/logout-all, lockout, forgot/reset/change password, onboarding persistence, profile, settings, username, goal options, target calculation (nutrition steps 1–6 + hydration base need), entitlements read, and consent capture at onboarding completion.

**In:** doc 04 §2.1, §2.2, §2.3, `GET /me/entitlements`, `POST /privacy/consents`; `domain/nutrition/calculator.py` (BMR→macros), `domain/hydration/calculator.py` (LBW→need, base at 25 °C); OTP emails over SMTP (dev: outbox folder).
**Out:** Flutter screens (S07); tracking (S08+).

## Prerequisites
S02, S03, S04. Decisions (or defaults) for OQ-13, OQ-14, OQ-22, OQ-24–OQ-31, OQ-34.

## Files to create / modify

### naraacare-backend
```
app/api/v1/routers/auth.py me.py reference.py privacy.py (consents only)
app/schemas/auth.py me.py reference.py privacy.py
app/core/security/tokens.py          # EdDSA JWT issue/verify (kid), refresh token generation
app/core/security/authz.py           # current_user, require_role, require_username, require_entitlement
app/core/security/oauth_google.py oauth_apple.py
app/core/security/passwords.py       # policy (doc 00 OQ-29) + common-password list (data/common_passwords.txt, 10k)
app/domain/nutrition/calculator.py   # bmr, tdee, bmi, allowed_goals, goal_target, safety_floor, macros, healthy_range
app/domain/hydration/calculator.py   # lean_body_weight, water_movement, need, rates, tank (status in S09)
app/domain/common/rounding.py units.py
app/domain/entitlements/service.py   # wraps billing.fn_current_entitlement + Redis cache 60 s
app/repositories/auth_repo.py profile_repo.py reference_repo.py privacy_repo.py
app/integrations/email.py            # templated OTP email (autoescape), no user text; smtp + dev outbox backends
app/templates/email/otp_verification.txt/.html, password_reset.*, lockout_notice.*
tests/unit/domain/nutrition/test_examples.py tests/unit/domain/hydration/test_examples.py
tests/integration/test_auth_flow.py test_oauth.py test_profile.py test_onboarding.py
tests/security/test_auth_security.py (JWT tampering, reuse, lockout, enumeration, mass assignment, IDOR on profile)
```

### naraacare-database
```
functions/R__24_app.fn_goal_options_context.sql   # (if needed) bmi categories + goals
procedures/ (S03 auth/app procs) — adjust as implementation reveals
tests/160_auth_integration.sql
```

## Step-by-step tasks
1. **Sign-up**: validate → reject if email_bidx exists (409 `EMAIL_REGISTERED`, rate-limited; OQ-26) → hash password → `pr_create_account` → OTP generated (Python), hash stored → email (SMTP) → 201 challenge.
2. **OTP verify**: load challenge → Argon2 verify (constant time) → `pr_verify_otp(p_code_ok)` → on success activate + issue tokens; on failure return attempts left; 3 failures → challenge dead (user must resend).
3. **Login**: blind-index lookup → if locked → 423 → verify password (always run a dummy Argon2 verify when the account doesn't exist, for constant timing) → `pr_record_login_attempt` → tokens. Rehash if params changed.
4. **Google/Apple**: verify tokens (doc 07 SEC-1.4) → find identity → else find by email_bidx → if a password account exists → 409 `LINK_REQUIRED` with a short-lived signed `link_token` → `/auth/oauth/link` after password proof; else create an active account (email verified by provider).
5. **Refresh**: `pr_rotate_refresh_token` → reuse → revoke family, security event, 401.
6. **Forgot/reset/change password**: generic 202 response; OTP purpose `password_reset`; history check (last 5) + policy; revoke all sessions; notify email.
7. **Onboarding**: `PUT /me/onboarding/steps/{n}` with step-specific schemas; `GET /me/onboarding` resume; `POST /calculations/preview`; `POST /me/onboarding/complete` → compute snapshot (nutrition + hydration base need at 25 °C, `calc_version` from DB) → `pr_complete_onboarding` + consents (`terms`, `privacy`, `health_data` required; `ai_processing` optional).
8. **Profile/settings/username/goal options/targets/entitlements** endpoints; profile updates recompute **today's** snapshot only.
9. Encrypt email + full name + medical conditions on write; decrypt on read for the owner only.
10. Add every new route to the payload sweep (automatic via OpenAPI) and to the IDOR suite.

## DB objects
Uses S03 auth/app procedures; may add `app.fn_goal_options_context`. No new tables.

## API endpoints
`POST /auth/signup`, `/auth/otp/verify`, `/auth/otp/resend`, `/auth/login`, `/auth/oauth/google`, `/auth/oauth/apple`, `/auth/oauth/link`, `/auth/token/refresh`, `/auth/logout`, `/auth/logout-all`, `/auth/password/forgot`, `/auth/password/reset`, `/auth/password/change`; `GET /me`, `PATCH /me/profile`, `PUT /me/settings`, `GET /me/onboarding`, `PUT /me/onboarding/steps/{step}`, `POST /calculations/preview`, `POST /me/onboarding/complete`, `GET /me/goal-options`, `GET /me/targets/today`, `GET /usernames/availability`, `PUT /me/username`, `GET /me/entitlements`; `GET /reference/bootstrap`, `GET /reference/policies`; `GET/POST /privacy/consents`.

## Screens
None (S07 builds A1–A11, O0–O7, ST2–ST4 against these endpoints).

## Security checks
SEC-1.1–1.6 all; SEC-3.2 auth rate limits; T1–T5, T26 mitigations; SEC-4.5 encryption of email/name/conditions; SEC-7.1 consent records with policy version; SEC-7.3 no mobile/DOB stored; tokens never logged.

## Input-validation checklist
New string fields and their types:
- [ ] `email` SafeEmail(254) · `password`/`confirm_password`/`new_password`/`current_password` SafePassword(8–128) · `code` SafeOtp · `id_token`/`identity_token` SafeOpaqueToken(4096) · `authorization_code` SafeOpaqueToken(512) · `nonce` SafeOpaqueToken(128) · `link_token` SafeOpaqueToken(512) · `refresh_token` SafeOpaqueToken(256) · `full_name`/`given_name` SafeName(100) · `username` SafeUsername · `timezone` SafeTimezone · `locale` SafeLocale · `medical_condition_codes[]` SafeShortText(40) + must exist in ref · `policy_version` SafeShortText(20) · `referral_code` SafeReferralCode.
- [ ] Matching DB domains/CHECKs exist (username domain; ciphertext for name/email/conditions).
- [ ] All of the above covered by the payload sweep (auto) — verified count in test output.

## Tests to write
Calculator unit tests for every doc 06 example + boundaries (BMI, floor, goals); sign-up → OTP → tokens; OTP wrong ×3, expired, resend cooldown; login lockout/backoff; constant-time path for unknown email (timing variance check, loose); refresh rotation + reuse detection; logout-all; password reset revokes sessions; password reuse rejected; Google/Apple token verification with mocked JWKS (wrong aud/iss/nonce/expired → 401); link flow; onboarding resume; preview equals completed snapshot; profile edit creates today's snapshot only; username 90-day rule; mass-assignment (`role`, `tier`) → 422; JWT tampering suite.

## Acceptance criteria / Definition of done
- [ ] Full auth flows work against the local stack, with OTP emails landing in `var/outbox/` (no user text inside, never in logs).
- [ ] Doc 06 nutrition examples 1 & 2 and Kompal/Sahil base needs reproduced by `/calculations/preview` for equivalent profiles.
- [ ] BMI-blocked goals rejected server-side.
- [ ] Refresh token reuse revokes the family and logs a security event.
- [ ] No endpoint accepts `user_id` from the client; IDOR suite green.
- [ ] Payload sweep green for all new fields; OpenAPI snapshot committed.
- [ ] Email, full name and conditions are ciphertext in the DB (verified by test reading raw table as owner).

## Estimated effort
7–8 developer-days.

## Implementation status (2026-10-29)

Verified locally against a migrated PostgreSQL 18.6 (native install, the same scripts CI runs). Nothing is committed yet.

| Acceptance criterion | Status |
|---|---|
| Full auth flows against the local stack, OTP emails in `var/outbox/` (no user text, never logged) | ✅ 26 database-backed flow tests: sign-up → code → tokens, wrong code ×3 → `OTP_LOCKED`, resend cooldown, sign-in, generic failures, lockout after 5 with a notice email, unverified account, refresh rotation + reuse (family revoked), refresh from another installation refused, logout / logout-all (access token refused at once), forgot/reset (reuse refused, code survives), change password, Google sign-in, `LINK_REQUIRED` + link with password, Apple with encrypted refresh token. Email tests check that codes and recipients never reach the logs |
| Doc 06 nutrition examples 1 & 2 and Kompal/Sahil base needs reproduced | ✅ unit tests (1680/1714/2214/304/62/111; 1364/1023/1200 floor/165/33/60; Kompal 46.05 kg, 3,592 → 3,053 mL, 2,880 at 22 °C, 3,844 at 35 °C; Sahil 60.09 kg, 4,761, 5,047 mL) and `/calculations/preview` = completed snapshot for example 1 |
| BMI-blocked goals rejected server-side | ✅ 422 `GOAL_NOT_ALLOWED` when saving step 3 and on profile edits; half-open BMI boundaries on the unrounded value |
| Refresh-token reuse revokes the family and logs a security event | ✅ (database procedure from S03 + API test) |
| No endpoint accepts `user_id` from the client; IDOR | ✅ every user route takes the user from the token; mass-assignment (`role`, `tier`, `user_id`) → 422; the JWT tampering suite rejects forged roles/subjects, `alg: none`, HMAC-with-public-key, foreign keys, wrong audience/issuer, unknown `kid` |
| Payload sweep green for all new fields | ✅ 31 operations, 33 string fields (plus the 8 echo fields) × 538 payloads = 21,982 hostile requests, all 422, none echoed or logged. Secured routes are swept with a valid token |
| Email, full name and conditions are ciphertext in the DB | ✅ read back as the database superuser in tests |
| Quality gates | ✅ 507 backend tests (96.3 % coverage; `app/core/security` 97 %), ruff, mypy --strict, bandit, Semgrep (custom 5/5 + 158 OWASP/Python rules, 0 findings), pip-audit clean. Database: 905 pgTAP assertions (new `tests/160`), no drift, sqlfluff clean |

Database changes: `auth.fn_otp_challenge_email` (resend needs the address), `auth.pr_rehash_password` (rehash on sign-in without touching history or sessions), `auth.pr_store_provider_token` + column `auth.identity_link.provider_refresh_token_ct` (`V016`; Apple revocation, SEC-1.4), `ref.fn_calc_context`, `ref.fn_policies`, `privacy.fn_current_consents`, and `app.fn_get_profile` now returns `age_recorded_on` (current age is derived, OQ-31).

Decisions and deviations (docs 00, 03, 04, 05, 07, 08 updated):
- **API changes to doc 04:** `installation_id` added to OTP verify, refresh and link (refresh tokens are bound to the installation); logout takes no body (the session is the token's `sid`); settings and username return 204; entitlements return the database feature codes; new errors `OTP_LOCKED` (423), `EMAIL_NOT_VERIFIED` (403, with a new code sent), `GOAL_NOT_ALLOWED` (422).
- **Deferred:** referral code at sign-up → S11 (attributed from the install/deep link); Apple `given_name` is not sent to the API (the app pre-fills onboarding step 1).
- **Token revocation within 15 minutes:** Redis deny-list per session and a per-user cut-off (millisecond `iat_ms` claim); fails open if Redis is down (refresh tokens are revoked in the database regardless).
- **Dev keys:** without `JWT_PRIVATE_KEY_PEM` the API generates an ephemeral key in dev (refused elsewhere); `tools/new_jwt_key.py` makes real keys. No key material in `.env.example`.
- **Provider verification with PyJWT** (instead of `google-auth`), same checks; JWKS cached 1 h with a rate-limited early refresh. New pins: `pyjwt 2.15.1`; `httpx2` became a runtime dependency.
- **Emails** use fixed `string.Template` files with an allow-list on values (codes and numbers only) instead of Jinja2: there is no user text to escape. Error-path emails (lockout notice, new verification code) are sent inline because FastAPI drops background tasks when a route raises.
- **Strict models** keep strings and numbers strict; UUID, decimal and time fields opt out individually (`app/schemas/common.py`), because FastAPI validates parsed JSON in Python mode.
- **New `SafeCode40`** type for reference codes (same format as the database domain `common.code`).
- **Coverage** now traces greenlets (SQLAlchemy's async layer); before, every line after an awaited query was reported as missed.
- **CI:** the backend job installs PostgreSQL 18 and Flyway on the runner and migrates `naraacare-database` (checked out at `DATABASE_REF` with a read-only token), so the database tests run on every PR. Not run yet: the GitHub repos do not exist.

Open: OQ-26 copy approval (the sign-up "already registered" message), OQ-60 (strict reuse detection is the default), OQ-12/OQ-13 (multipliers and activity mapping need nutritionist sign-off).
