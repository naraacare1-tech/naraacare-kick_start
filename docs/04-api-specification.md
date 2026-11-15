# 04 — API Specification (`/api/v1`)

## 1. Conventions

| Item | Rule |
|---|---|
| Base URL | `https://api.naraacare.app/api/v1` (prod), `api.staging.…`, `api.dev.…` — from env |
| Format | JSON only. `Content-Type: application/json; charset=utf-8` on every response, `X-Content-Type-Options: nosniff`. Multipart only on `POST /support/tickets`. |
| Auth | `Authorization: Bearer <access JWT>` (15 min, EdDSA/Ed25519). Endpoints marked **Public** need none. |
| Identity | `user_id` is **never** accepted from the client for the caller's own data; it comes from the token `sub`. Path IDs of other objects are ownership-checked (object-level authorisation) in the DB function. |
| IDs | UUIDv7 strings. Validated by Pydantic `UUID` (not Safe* strings). |
| Times | RFC 3339 with offset; server stores UTC. `date` = `YYYY-MM-DD` in the user's timezone. |
| Pagination | Cursor: `?cursor=<opaque>&limit=<1..50, default 20>`. Response `{items:[], next_cursor}`. `cursor` → `SafeOpaqueToken(max 256)`. |
| Idempotency | Creates from the app carry `client_entry_id` (UUIDv7). Repeating the same id returns `200` with the original resource. `Idempotency-Key` header (UUID) on purchase verify, report and export creation. |
| Concurrency | Updatable resources return `version` (int). `PUT`/`DELETE` require `If-Match: <version>`; a mismatch gives `409 VERSION_CONFLICT` with the current server copy in `error.current` (the same representation a `GET` returns, including `version`); the app replaces its local copy with it and flags the entry (server wins, S06). |
| Versioning | URL prefix `/api/v1`. Breaking changes → `/api/v2`. `X-Min-App-Version` response header lets the app force an update. |
| Request ID | `X-Request-ID` accepted (UUID format, else replaced) and always returned. |
| Limits | Body ≤ 1 MB (10 MB on ticket upload). Strings: every field has a max length (below). Arrays have `max_length`. |
| Docs | OpenAPI at `/api/v1/docs` only when `API_DOCS_ENABLED=true` (dev/staging, behind basic-auth on staging). Disabled in prod. |

### 1.1 Error envelope (uniform)

```json
{ "error": { "code": "VALIDATION_FAILED", "message": "Input contains characters that are not allowed", "fields": ["full_name"], "request_id": "0192f7c0-…" } }
```
Never contains stack traces, SQL, internal IDs or the rejected input.

DB error mapping (S03, `naraacare-database/functions/README.md`): `22023` → 422 `VALIDATION_FAILED`; `23514`/`23503` (CHECK/FK) → 422 `VALIDATION_FAILED`; `42501` → 404 `NOT_FOUND`; `P0001` → the app code in the error's `DETAIL` with the status from this table; `40001` → retried once, then 503. Auth procedures report expected outcomes (`invalid`, `dead`, `expired`, `rate_limited`, `reuse_detected`, `locked` …) in an `o_status` output instead of raising, so counters persist; the API maps them to the codes above.

| HTTP | `code` | When |
|---|---|---|
| 400 | `BAD_REQUEST` | malformed JSON, bad header |
| 401 | `UNAUTHENTICATED`, `TOKEN_EXPIRED`, `INVALID_CREDENTIALS` | missing/expired token; login failure (generic) |
| 403 | `FORBIDDEN` | role/ownership failure (returned as 404 for object lookups to avoid ID probing) |
| 403 | `UPGRADE_REQUIRED` (+ `feature`) | STAR-only feature |
| 403 | `DAILY_LIMIT_REACHED` (+ `limit`) | meal logs, Rin allowance |
| 403 | `EDIT_WINDOW_CLOSED` | edit outside last-2 / 7-day rule |
| 403 | `CUSTOM_DRINK_LIMIT` | more than 100 custom drinks (S09) |
| 409 | `PURCHASE_TOKEN_IN_USE` | the store purchase belongs to another account (S11) |
| 422 | `PURCHASE_INVALID` | the store did not confirm the purchase (S11) |
| 409 | `SLEEP_OVERLAP` | a sleep entry overlaps another (S10) |
| 422 | `WATER_BELOW_ZERO` | a swipe-down, edit or delete would make the day's water negative (S09) |
| 403 | `CONSENT_REQUIRED` (+ `purpose`) | AI features without `ai_processing` consent; sharing without `circle_sharing` consent |
| 403 | `USERNAME_REQUIRED` | social endpoints before a username is set |
| 403 | `EMAIL_NOT_VERIFIED` (+ `challenge_id` when a new code was sent) | correct password on an account whose email is not verified yet (S05) |
| 404 | `NOT_FOUND` | missing or not owned |
| 409 | `VERSION_CONFLICT`, `ALREADY_EXISTS`, `USERNAME_TAKEN`, `EMAIL_REGISTERED` | |
| 409 | `ONBOARDING_INCOMPLETE`, `ONBOARDING_ALREADY_COMPLETED`, `IDENTITY_ALREADY_LINKED`, `LINK_REQUIRED` | state conflicts raised by the DB (S03) |
| 403 | `USERNAME_CHANGE_TOO_SOON` | second username change within 90 days |
| 403 | `ADMIN_REQUIRED` | circle action reserved for admins (S12) |
| 409 | `CIRCLE_FULL`, `LAST_ADMIN` | 50 members + open invites reached; the last admin cannot step down (S12) |
| 410 | `INVITE_LINK_EXPIRED` | invite link expired, used up or revoked (S12) |
| 422 | `QUERY_TOO_SHORT`, `SHARES_INVALID`, `MENTION_INVALID`, `TOO_MANY_MENTIONS`, `TOO_MANY_INVITEES` | social input rules (S12) |
| 429 | `INVITE_LINK_LIMIT` | more than 10 invite links per circle per day (S12) |
| 410 | `OTP_EXPIRED` | code past its 5 minutes |
| 413 | `PAYLOAD_TOO_LARGE` | |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | |
| 422 | `VALIDATION_FAILED` | Pydantic / Safe* rejection (generic message) |
| 422 | `OTP_INVALID` (+ `attempts_left`), `PASSWORD_WEAK`, `PASSWORD_REUSED`, `GOAL_NOT_ALLOWED` | wrong code; password policy (OQ-29); goal blocked by BMI (doc 06 §2.3) |
| 423 | `ACCOUNT_LOCKED` (+ `retry_after_s`), `OTP_LOCKED` | sign-in lockout; third wrong code (request a new code) |
| 429 | `RATE_LIMITED` (+ `Retry-After`) | rate limits |
| 429 | `REPORT_LIMIT_REACHED` / `SUPPORT_LIMIT_REACHED` | 10 reports / 5 tickets or feature requests per 24 h (S14) |
| 422 | `REPORT_RANGE_INVALID` / `UPLOAD_INVALID` | report dates; screenshot not a PNG/JPEG ≤ 10 MB (S14) |
| 409 | `REPORT_NOT_READY` | report file asked for before it is ready (S14) |
| 500/503 | `INTERNAL_ERROR` / `SERVICE_UNAVAILABLE` | |

### 1.2 Safe* types (backend `app/core/security/validators.py`)

All are `Annotated[str, SafeString(kind, max)]` (S04). Parameterised types are one alias per size (`SafeShortText20/40/60/120`, `SafeText500/2000`, `SafeOpaqueToken128/256/512/2048/4096/16384`); add an alias for a new size. Each publishes `maxLength` and `x-safe-kind` in OpenAPI. `SafeNewPassword` = `SafePassword` + one upper-case letter + one digit (OQ-29; the common-password list arrives in S05). Single-line types are trimmed. Pipeline: reject control chars/null bytes → NFKC normalise → iteratively URL-decode and HTML-entity-decode (max 3 passes) → reject patterns (doc 07 §4.2) → allow-list regex → length check (on the normalised value).

| Type | Max | Allow-list (after normalisation) |
|---|---|---|
| `SafeName` | 100 | Unicode letters + combining marks (incl. Indic scripts), space, `.` `'` `-`; must contain a letter |
| `SafeUsername` | 30 (min 3) | `^[a-z0-9](?:[a-z0-9._]{1,28})[a-z0-9]$`, no `..` `__` `._` `_.` (lower-cased first) |
| `SafeEmail` | 254 | RFC 5322 subset via `email-validator`, ASCII local part, lower-cased |
| `SafePassword` | 128 (min 8) | any printable Unicode **except** `<` `>`; no control chars; complexity rules on sign-up/reset only |
| `SafeOtp` | 6 | `^\d{6}$` |
| `SafeShortText(n)` | n ≤ 120 | letters, marks, digits, space, `. , ' - ( ) & / + %` |
| `SafeText(n)` | n ≤ 2000 | SafeShortText set + `! ? : ; " # @` + newline; no `<` `>` `{` `}` `` ` `` `$` `\` |
| `SafeChatMessage` | 2000 | SafeText set + emoji (`\p{Extended_Pictographic}`, ZWJ, VS16) |
| `SafeSearchQuery` | 64 (min 1) | letters, marks, digits, space, `. ' - & @ _` |
| `SafeOpaqueToken(n)` | n (256 default; 16384 for store JWS) | `^[A-Za-z0-9._~+/=-]+$` |
| `SafeReferralCode` | 12 (min 6) | `^[A-Z0-9]{6,12}$` (upper-cased) |
| `SafeBarcode` | 14 (min 8) | `^\d{8,14}$` + GTIN checksum |
| `SafeTimezone` | 64 | member of `zoneinfo.available_timezones()` |
| `SafeLocale` | 5 | `^[a-z]{2}(-[A-Z]{2})?$`, in supported set (`en`, `en-IN`, `hi`, `hi-IN`) |
| `SafeFileName` | 100 | `^[A-Za-z0-9 _.-]{1,95}\.(png|jpg|jpeg)$`, no `..` |
| `SafeAppVersion` | 20 | `^\d+\.\d+\.\d+(\+\d+)?$` |
| `SafeDeviceToken` | 4096 | `^[A-Za-z0-9:_-]+$` (FCM token) |

**Code-review rule:** a `str` field in any `schemas/` model that is not one of these types fails CI (custom ruff/semgrep rule `no-bare-str-in-schemas`). Enums use `Literal[...]`/`Enum`; numbers use `conint`/`condecimal` with ranges.

---

## 2. Endpoints

Columns: **Auth** (Public / User / Admin / Nutritionist / Webhook) · **Tier** (— = both) · **Rate** = per-route limit beyond the global default (300 req/min/user, 600 req/min/IP).

### 2.1 Auth

| Method & path | Auth | Request | Response | Errors | Rate |
|---|---|---|---|---|---|
| `POST /auth/signup` | Public | `email: SafeEmail`, `password: SafePassword`, `confirm_password: SafePassword`, `accept_terms: true`, `policy_versions: {terms: SafeShortText(20), privacy: SafeShortText(20)}`, `installation_id: UUID` | 201 `{challenge_id, expires_in_s: 300, resend_after_s: 30}`; terms + privacy consents recorded | 409 `EMAIL_REGISTERED` (OQ-26), 422 `PASSWORD_WEAK`/`VALIDATION_FAILED` | 5/h/IP, 3/h/email |
| `POST /auth/otp/verify` | Public | `challenge_id: UUID`, `code: SafeOtp`, `installation_id: UUID` | 200 `TokenPair` | 422 `OTP_INVALID` (`attempts_left`), 410 `OTP_EXPIRED`, 423 `OTP_LOCKED` after 3 fails | 10/min/IP |
| `POST /auth/otp/resend` | Public | `challenge_id: UUID` | 202 `{resend_after_s}` (also for unknown ids: no enumeration) | 429 (30 s cooldown; 5/h/email in the DB) | 5/h/IP |
| `POST /auth/login` | Public | `email: SafeEmail`, `password: SafePassword`, `installation_id: UUID` | 200 `TokenPair` | 401 `INVALID_CREDENTIALS` (generic), 423 `ACCOUNT_LOCKED` (+ email notice), 403 `EMAIL_NOT_VERIFIED` | 10/min/IP, 5/15 min/account |
| `POST /auth/oauth/google` | Public | `id_token: SafeOpaqueToken(4096)`, `nonce: SafeOpaqueToken(128)`, `installation_id` | 200 `TokenPair` or 409 `LINK_REQUIRED` (OQ-30) | 401 | 10/min/IP |
| `POST /auth/oauth/apple` | Public | `identity_token: SafeOpaqueToken(4096)`, `authorization_code?: SafeOpaqueToken(512)`, `nonce`, `installation_id` | as Google; the code is exchanged in the background for Apple's refresh token (stored encrypted, used for revocation on deletion) | 401 | 10/min/IP |
| `POST /auth/oauth/link` | Public | `link_token: SafeOpaqueToken(2048)` (from the 409 `LINK_REQUIRED` body, 10 min), `password: SafePassword`, `installation_id` | 200 `TokenPair` | 401; counts as a sign-in attempt (lockout) | 5/15 min |
| `POST /auth/token/refresh` | Public | `refresh_token: SafeOpaqueToken(256)`, `installation_id: UUID` (tokens are bound to the installation) | 200 `TokenPair` (rotated) | 401; reuse or another installation → whole family revoked + security event | 30/min/IP |
| `POST /auth/logout` | User | — (the session is the token's `sid`) | 204; refresh family revoked, access token refused at once (Redis deny-list) | — | |
| `POST /auth/logout-all` | User | — | 204 (all families revoked, devices' push tokens kept) | — | |
| `POST /auth/password/forgot` | Public | `email: SafeEmail` | 202 `{challenge_id}` (always; generic — OQ-26) | 429 | 3/h/email, 10/h/IP |
| `POST /auth/password/reset` | Public | `challenge_id`, `code: SafeOtp`, `new_password: SafePassword`, `confirm_password: SafePassword` | 204 (all sessions revoked, notice email) | 422 `PASSWORD_REUSED` (the code stays usable), `PASSWORD_WEAK`, `OTP_INVALID`; 410; 423 | 10/h/IP |
| `POST /auth/password/change` | User | `current_password`, `new_password`, `confirm_password` (SafePassword) | 204 (other sessions revoked) | 401, 422 | 5/h |

`TokenPair = {access_token, access_expires_in_s: 900, refresh_token, refresh_expires_in_s: 5184000, token_type: "Bearer", onboarding_required: bool}`.

Notes (Session 05): the referral code is not part of sign-up yet; Session 11 attributes referrals from the install/deep link. Apple's `given_name` is not sent to the API: the app pre-fills onboarding step 1 with it (the name is stored once, encrypted, at step 1). Nonces: the app passes SHA-256(hex) of a random raw nonce to Google/Apple and the raw nonce to the API.

### 2.2 Me, onboarding, targets

| Method & path | Auth | Request | Response | Notes |
|---|---|---|---|---|
| `GET /me` | User | — | profile (decrypted name), username, units, timezone, tier, onboarding state, counts (connections, circles, streak) | |
| `PATCH /me/profile` | User | any of: `full_name: SafeName`, `biological_sex`, `age_years: 18..100`, `height_cm: 120..230 (1 dp)`, `weight_kg: 30..250 (2 dp)`, `target_weight_kg`, `weight_goal`, `activity_level`, `body_type`, `medical_condition_codes: list[SafeShortText(40)] ≤ 20` (must exist in ref), `avatar_code: Literal` | updated profile + `targets_today` | today's targets recalculated; past days untouched (DOC flag) |
| `PUT /me/settings` | User | `height_unit: cm|ft_in`, `weight_unit: kg|lb`, `temperature_unit: c|f`, `timezone: SafeTimezone`, `locale: SafeLocale`, `sleep_start_local: HH:MM`, `wake_local: HH:MM`, `biometric_lock: bool` | 204 | |
| `GET /me/onboarding` | User | — | `{current_step, data_so_far}` | resume |
| `PUT /me/onboarding/steps/{step}` | User | step 1: `biological_sex`, `avatar_code` (must match the sex), `full_name: SafeName`; 2: `height_cm`; 3: `weight_kg`, `weight_goal` (BMI guardrails → 422 `GOAL_NOT_ALLOWED`); 4: `target_weight_kg`, `medical_condition_codes?: list[SafeCode40]`; 5: `age_years`, `activity_level`; 6: `body_type`. Only that step's fields may be sent. | 200 `{current_step}` | step ∈ 1..6, no skipping |
| `POST /calculations/preview` | User | — (uses saved onboarding data) | `{bmi, bmi_category, healthy_weight_range_kg, targets: {kcal, carbs_g, fat_g, protein_g, safety_override}, water_need_ml}` | result page |
| `POST /me/onboarding/complete` | User | `consents: [{purpose, policy_version: SafeShortText(20), granted}]` | 201 `targets_today` | creates `app.health_target_snapshot` |
| `GET /me/goal-options` | User | query `weight_kg`, `height_cm` (optional; default saved) | `{bmi, category, allowed_goals[], healthy_weight_range_kg}` | BMI guardrails (doc 06 §2.3) |
| `GET /me/targets/today` | User | — | nutrition + hydration targets | |
| `GET /usernames/availability` | User | `username: SafeUsername` | `{available: bool}` | 30/min/user |
| `PUT /me/username` | User | `username: SafeUsername` | 204 | 409 `USERNAME_TAKEN`, 403 `USERNAME_CHANGE_TOO_SOON` |
| `GET /me/entitlements` | User | — | `{tier, source, expires_at, features: {<ref.feature_entitlement code>: bool}, limits: {<code>: int}}` — codes as seeded: `sleep, rin_ai, voice_logging, barcode_logging, meal_breakdown, advanced_hydration, premium_drinks, custom_drinks, custom_report, report_insights, nutrients_visible, meal_logs_per_day` (cached 60 s) | |

### 2.3 Reference

| Method & path | Auth | Response |
|---|---|---|
| `GET /reference/bootstrap` | Public (ETag, `Cache-Control: max-age=3600`) | activity levels, body types, weight goals, BMI categories, drinks, workouts, nutrients (label, unit, tier), units & portions, medical conditions, avatars, wallpapers, report sections, suggested Rin prompts, min app version |
| `GET /reference/policies` | Public | current policy docs `{type, version, url, published_at}` |

### 2.4 Foods and nutrition

| Method & path | Auth | Tier | Request | Response | Errors |
|---|---|---|---|---|---|
| `GET /foods/search` | User | — | `q: SafeSearchQuery`, `limit ≤ 25` | `[{food_id, name, default_portion_label, kcal_per_default}]` (trigram + alias match) | 30/min |
| `GET /foods/{food_id}` | User | — | — | food + available units `[{unit_code, size, label, grams}]` + nutrients per 100 (tier-filtered) | 404 |
| `GET /foods/barcode/{code}` | User | STAR | path `code: SafeBarcode` | product or `{found:false}` | 403 UPGRADE |
| `POST /nutrition/voice/parse` | User | STAR | `transcript: SafeText(300)`, `locale: SafeLocale` | `{items:[{food_id, name, quantity, unit_code, confidence}], unmatched:[SafeShortText]}` (user confirms) | 403 |
| `POST /meals` | User | — (source voice/barcode → STAR) | `client_entry_id: UUID`, `logged_at`, `meal_type: breakfast|lunch|dinner|snack`, `source: search|voice|barcode|saved|rin`, `items: [{food_id: UUID, quantity: 0.25..20, unit_code: Literal, unit_size?: small|medium|large|half|full}] (1..30)` | 201 `{meal, daily_summary, avatar}` | 403 `DAILY_LIMIT_REACHED`, 422 |
| `PUT /meals/{meal_id}` | User | — | `If-Match`; `meal_type`, `items` | 200 | 403 `EDIT_WINDOW_CLOSED`, 409 |
| `DELETE /meals/{meal_id}` | User | — | `If-Match` | 204 | 403, 409 |
| `GET /meals` | User | — | `date`, cursor | meals with items | |
| `GET /meals/recent` | User | — | `limit ≤ 10` | recent meals + recent food chips + `editable` flag | |
| `GET /meals/{meal_id}/breakdown` | User | STAR | — | per-meal 17 nutrients + macro % | 403 |
| `GET /nutrition/daily-summary` | User | — (filtered) | `date` | `{date, totals:{6 or 17}, locked_nutrients_count, target_kcal, effective_allowance_kcal, exercise_kcal, avatar:{fill_pct, state}, meal_count, meal_limit, last_updated}` | |
| `GET /saved-meals` / `POST /saved-meals` / `DELETE /saved-meals/{id}` | User | — | POST: `name: SafeShortText(60)`, `items[]` (as meals, ≤ 30) | | max 50 saved meals |

### 2.5 Activity and hydration

| Method & path | Auth | Tier | Request | Response | Errors |
|---|---|---|---|---|---|
| `POST /workouts` | User | STAR (OQ-04) | `client_entry_id`, `workout_type: walking|gym|cycling|swimming|running|trekking`, `duration_min: 1..600`, `performed_at` | 201 `{workout, sweat_ml, kcal}` | 403 |
| `GET /workouts` / `DELETE /workouts/{id}` | User | STAR | `date` | | |
| `GET /hydration/drinks` | User | — | — | drinks + factor + `locked` flag + user's custom drinks | |
| `POST /hydration/intakes` | User | — (drink tier checked) | `client_entry_id`, `logged_at`, `drink_code?: Literal` or `custom_drink_id?: UUID` (exactly one), `volume_ml: -100 or 1..3000`, `source: swipe|manual|preset|rin` (−100 only with `swipe` + water) | 201 `{intake, status}` | 403, 422 |
| `PUT /hydration/intakes/{id}` / `DELETE` | User | — | `If-Match`; `volume_ml`, `drink_code` | 200 / 204 | 403 `EDIT_WINDOW_CLOSED` |
| `GET /hydration/intakes` | User | — | `date` | list | |
| `GET /hydration/status` | User | — | `date?` (default today; a past day within 7 days returns its end-of-day status; S09) | `{level_pct, band: well|drink_soon|low|critical, balance_ml, tank_ml, daily_goal_ml, effective_intake_ml, consumed_pct, left_to_drink_ml, state: empty|in_progress|goal_completed|above_goal|day_ending_soon, temperature: {c, set_at, stale}, overhydration_caution: bool, calc_version}` | |
| `PUT /hydration/temperature` | User | STAR | `temperature_c: 15.0..40.0` (1 dp) | 200 status | 403 |
| `POST /hydration/custom-drinks/estimate` | User | STAR | `name: SafeShortText(60)` | `{hydration_factor, source: ai|default, explanation_code}` | 403, Rin allowance |
| `POST /hydration/custom-drinks` | User | STAR | `name: SafeShortText(60)`, `hydration_factor: 0..1 (3 dp)`, `source?: ai|default|user` | 201 | 403 `CUSTOM_DRINK_LIMIT` (max 100), 409 `ALREADY_EXISTS` (name per user, case-insensitive) |

### 2.6 Sleep (STAR)

| Method & path | Request | Response | Errors |
|---|---|---|---|
| `POST /sleep/entries` | `client_entry_id`, `sleep_start`, `wake_time` (≤ 16 h apart, wake > start, wake ≤ now + 5 min), `wakings: [{woke_at, back_asleep_at}] ≤ 10` | 201 `{entry, summary}` | 403 UPGRADE, 422 overlap |
| `PUT /sleep/entries/{id}` / `DELETE` | `If-Match` + as above | 200 / 204 | 403 `EDIT_WINDOW_CLOSED` |
| `GET /sleep/summary` | `date?` (default today) | `{date, counted_min, goal_min, score_pct, label: good|fair|low|none, buffers: {onset_min, wake_min, waking_min}, entries: [{entry_id, sleep_start, wake_time, counted_min, version, editable, wakings[]}]}` (S10) | 403 |
| `PUT /me/sleep-goal` | `goal_min: 240..720` | 200 `{goal_min}` (every tier; today's score is recomputed, S10) | |

### 2.7 Streak, notifications, devices, reminders

| Method & path | Request | Response |
|---|---|---|
| `GET /me/streak` | `month?: YYYY-MM` (SafeYearMonth; default this month) | `{current, longest, broken_yesterday, today, days:[{date, active}] (month up to today), last_7_days:[{date, active}]}` (S14; "broken" = nothing yesterday or today, the day before active) |
| `GET /notifications`, `POST /notifications/read` | see section 2.9 (S12; the personal list is the same endpoint without `circle_id`) | S14 templates: `streak_milestone {days}`, `report_ready {report_id, from, to}`, `report_failed {report_id}` |
| `GET /me/notification-preferences`, `PUT` | 12 booleans (doc 05 `notify.notification_preference`) | |
| `GET /me/reminders`, `PUT` | `{reminders: [{type: hydration|nutrition|sleep|daily_checkin|health_profile, enabled, times: [HH:MM] ≤ 12 or interval_min: 60..240}]}` (S09: wrapped in an object; unsaved types come back disabled with suggested times and `saved: false`) | |
| `POST /devices` | `installation_id: UUID`, `platform: android|ios`, `push_token: SafeDeviceToken`, `app_version: SafeAppVersion` | 201 |
| `DELETE /devices/{installation_id}` | — | 204 |

### 2.8 People, connections, blocks

| Method & path | Request | Response | Errors |
|---|---|---|---|
| `GET /people/search` | `q: SafeSearchQuery` (≥ 3 chars, username prefix) | `[{user_id, username, display_initial, avatar_code, connection_status}]` ≤ 20; blocked users hidden both ways | 30/min |
| `GET /people/suggestions` | — | ≤ 20 circle co-members you are not connected to (friends-of-connections later) | |
| `GET /connections` | cursor | connections + pending invites | |
| `POST /connections/requests` | `username: SafeUsername` | 201 `{connection_id, status: pending|accepted|already_connected}` | 404 |
| `POST /connections/requests/{id}/accept` / `/decline` | — | 204 | 404 |
| `DELETE /connections/{id}` | — | 204 | |
| `GET /blocks`, `POST /blocks` (`user_id: UUID`), `DELETE /blocks/{user_id}` | | | |

Username required (403 `USERNAME_REQUIRED`) for all social endpoints.

### 2.9 Care Circles and chat

| Method & path | Auth | Request | Response | Errors |
|---|---|---|---|---|
| `GET /circles` | User | — | circles `{id, name, wallpaper, member_count, updates_today, unread}` | |
| `POST /circles` | User | `name: SafeShortText(50)`, `invitee_user_ids: list[UUID] ≤ 49`, `shared_avatars: list[hydration|nutrition|sleep] (1..3)` | 201 circle | 403 sleep without STAR, 422 |
| `GET /circles/{id}` | Member | — | circle, members preview, last chat preview | 404 |
| `PATCH /circles/{id}` | Admin | `name?: SafeShortText(50)`, `wallpaper_code?: Literal` | 200 | 403 |
| `DELETE /circles/{id}` | Admin | — | 204 | |
| `POST /circles/{id}/members` | Admin | `user_ids: list[UUID] ≤ 49` | 201 invites | 409 `CIRCLE_FULL` (50) |
| `DELETE /circles/{id}/members/{user_id}` | Admin | — | 204 | |
| `PUT /circles/{id}/members/{user_id}/role` | Admin | `role: admin|member` | 204 | 409 `LAST_ADMIN` |
| `POST /circles/{id}/leave` | Member | — | 204 (admin succession rule) | |
| `GET /circles/{id}/members` | Member | `q?: SafeSearchQuery`, cursor | admins, members, invited | |
| `GET /circles/{id}/members/{user_id}/avatars` | Member | — | shared avatars' current state; sleep only if both STAR; `not_shared` flags | 404 |
| `PUT /circles/{id}/shares` | Member | `shared_avatars (1..3)` | 200 (removed shares hide past data) | 422 `SHARES_INVALID`, 403 sleep without STAR |
| `GET /circles/{id}/feed` | Member | cursor | Recent Updates events | |
| `GET /circle-invites` | User | — | pending invites | |
| `POST /circle-invites/{circle_id}/accept` | User | `shared_avatars (1..3)` | 200 | 409 full |
| `POST /circle-invites/{circle_id}/decline` / `/later` | User | — | 204 | |
| `POST /circles/{id}/invite-links` | Admin | `max_uses?: 1..49` | 201 `{link_id, url: https://<REFERRAL_LINK_DOMAIN>/circle/<token>, expires_at}` (token shown once; only its SHA-256 is stored) | 429 `INVITE_LINK_LIMIT` (10/day) |
| `DELETE /circles/{id}/invite-links/{link_id}` | Admin | — | 204 | |
| `POST /invite-links/resolve` | User | `token: SafeOpaqueToken(64)` | `{circle_id, status: invited|member, name, inviter_username, member_count}` + creates invite | 404, 410 `INVITE_LINK_EXPIRED`, 409 `CIRCLE_FULL`; 10/min |
| `GET /circles/{id}/messages` | Member | `before?` cursor, `limit ≤ 50` | `{items, next_before}` (plain text) | |
| `POST /circles/{id}/messages` | Member | `client_message_id: UUID`, `body: SafeChatMessage`, `mention_user_ids: list[UUID] ≤ 20` | 201 (200 on a replay) | 422 `MENTION_INVALID` / `TOO_MANY_MENTIONS`; 30/min/user |
| `POST /circles/{id}/messages/read` | Member | — | 204 (unread count resets) | |
| `DELETE /circles/{id}/messages/{message_id}` | Sender or Admin | — | 204 | |
| `PUT /circles/{id}/notification-settings` | Member | 6 booleans: `member_join_leave, circle_updates, goal_completions, avatar_updates, mentions, new_messages` | 200 | |
| `GET /notifications` | User | `circle_id?`, `before?`, `limit ≤ 50` | `{items: [{notification_id, created_at, circle_id, category, template_code, params, deep_link, read_at}], next_before}` (90 days) | 404 if not a member of `circle_id` |
| `POST /notifications/read` | User | `circle_id?`, `ids?: list[UUID] ≤ 100` | 204 | |
| `POST /realtime/ticket` | User | — | `{ticket, expires_in_s: 30}` | |
| `GET /ws?ticket=` (WebSocket) | Ticket (single use, 30 s) | client → server: `ping`, `typing` (circle_id); server → client: `pong`, `message.created`, `message.deleted`, `typing`, `circle.changed`, `notification` (`feed.event` later) | | ≤ 5 sockets/user, frames ≤ 8 KB, 20 per 10 s; one API process (in-memory fan-out) |

### 2.10 Rin AI (STAR)

| Method & path | Request | Response | Errors |
|---|---|---|---|
| `GET /rin/conversations` | `q?: SafeSearchQuery`, cursor | `[{id, title, last_message_at}]` | 403 |
| `POST /rin/conversations` | — | 201 `{conversation_id}` (titled from its first prompt) | |
| `GET /rin/conversations/{id}/messages` | cursor | messages | 404 |
| `POST /rin/conversations/{id}/messages` | `client_message_id: UUID`, `content: SafeChatMessage` | `text/event-stream`: `start {conversation_id}`, `delta {text}`, `action {action_id, kind: meal\|drink, payload}`, `done {text, usage_pct, resets_at}` or `error {code}` | 403 `UPGRADE_REQUIRED` / `CONSENT_REQUIRED` / `DAILY_LIMIT_REACHED`, 404, 422, 503; 20/min |
| `POST /rin/actions/{id}/accept` | `items?` (edited, same schema as meals) | 200 `{action_id, status, result}` (meal or intake, source `rin`) | 409 `ACTION_RESOLVED`, 410 `ACTION_EXPIRED` |
| `POST /rin/actions/{id}/dismiss` | — | 204 | |
| `DELETE /rin/conversations/{id}` | — | 204 | |
| `DELETE /rin/memory` | — | 204 (clears summaries) | |
| `GET /rin/usage` | — | `{used_pct, resets_at}` | |

### 2.11 Reports

| Method & path | Tier | Request | Response |
|---|---|---|---|
| `POST /reports` | monthly: both; custom: STAR | `Idempotency-Key`; `type: monthly|custom`, `month?: YYYY-MM`, `from?`, `to?` (≤ 366 days, not future), `sections: list[hydration|nutrition|sleep|insights]` (sleep/insights STAR unless OQ-38 rule) | 202 `{report_id, status}` |
| `GET /reports/{id}` | — | — | `{report_id, type, from, to, sections, status: queued|running|ready|failed|expired, download_url, size_bytes, created_at, expires_at}`; `download_url` is the API path below while there is no object store (S14) |
| `GET /reports/{id}/file` | owner | — | `application/pdf` (`Cache-Control: no-store`); 409 `REPORT_NOT_READY`, 404 for anyone else |
| `GET /reports` | — | `before?`, `limit ≤ 50` | `{items, next_before}` (last 12 months) |

S14 rules (database): 202 on create, 200 on a replay of the same key; monthly = whole month (to today for the current one); custom ≤ 366 days, not before 2026, STAR; sleep = STAR now or a monthly report of a month with sleep data (OQ-38: sleep can only be logged on STAR); insights = STAR + `ai_processing` consent (403 `CONSENT_REQUIRED`), generated from the period's averages only and counted against the Rin allowance; 10 requests / 24 h (429 `REPORT_LIMIT_REACHED`); 422 `REPORT_RANGE_INVALID`. Files are kept 7 days.

### 2.12 Billing and referral

| Method & path | Auth | Request | Response |
|---|---|---|---|
| `GET /billing/plans` | User | — | `{plans: [{platform, product_id, tier, period: monthly|yearly, display_price_inr}]}` (fallback; the app shows the store's price) |
| `POST /billing/purchases/verify` | User | `Idempotency-Key`; `platform: android|ios`, `product_id: Literal`, `purchase_token?: SafeOpaqueToken(2048)` (Android), `signed_transaction?: SafeOpaqueToken(16384)` (iOS, StoreKit 2 JWS) | 200 entitlements `{tier, source, expires_at, features, limits}`; 422 `PURCHASE_INVALID`, 409 `PURCHASE_TOKEN_IN_USE` (S11) |
| `GET /billing/subscription` | User | — | `{tier, source, status, platform, product_id, period, period_end, auto_renew, manage_url}` (`status: null` without a store subscription) |
| `GET /billing/history` | User | cursor, `limit ≤ 50` | `{items: [{date, product_id, platform, type: purchase|renewal|refund|revoke, amount, currency}], next_cursor}` |
| `POST /billing/webhooks/google` | Webhook (Pub/Sub push; OIDC JWT audience + service account verified) | Pub/Sub envelope | 204 |
| `POST /billing/webhooks/apple` | Webhook (ASSN v2 `signedPayload` verified against Apple root CA chain) | `signedPayload: SafeOpaqueToken(65536)` | 200 (401 if not authentic; replays are no-ops) |
| `GET /referrals/me` | User | — | `{code, link, required: 5, qualified, friends:[{username_or_initial, active_days, qualified}], reward_days, reward_granted_at}` |
| `POST /referrals/attribute` | User (new accounts ≤ 7 days old) | `code: SafeReferralCode`, `installation_id: UUID` | 204 (silently ignores invalid/self/duplicate) |

### 2.13 Privacy

| Method & path | Request | Response |
|---|---|---|
| `GET /privacy/consents` | — | current consent per purpose + policy version |
| `POST /privacy/consents` | `purpose: terms|privacy|health_data|ai_processing|circle_sharing|marketing`, `policy_version: SafeShortText(20)`, `granted: bool` | 201 (append-only record); 422 `CONSENT_WITHDRAWAL_BLOCKED` for withdrawing terms / privacy / health_data (that is the deletion path, S15) |
| `GET /privacy/status` | — | `{deletion: {requested_at, scheduled_for} | null, reconsent: [{doc_type, accepted_version, current_version, url}], latest_export}` (S15; re-consent when a published policy has a higher major version) |
| `POST /privacy/reauth` | — | 202 `{challenge_id}`; emails a 6-digit code (accounts without a password) |
| `POST /privacy/exports` | `Idempotency-Key`; proof: `password: SafePassword` or `challenge_id: UUID` + `code: SafeOtp` | 202 `{export_id, status}`, 200 on a replay; 429 `EXPORT_LIMIT_REACHED` (1 per 24 h); 401 `INVALID_CREDENTIALS` / 422 `OTP_INVALID` |
| `GET /privacy/exports/{id}` | — | `{export_id, status: queued|running|ready|failed|expired, requested_at, ready_at, expires_at, size_bytes, download_url}` (file kept 7 days) |
| `GET /privacy/exports/{id}/file` | owner | `application/zip` (README + JSON + CSV per table, `Cache-Control: no-store`); 409 `EXPORT_NOT_READY` |
| `POST /privacy/deletion-request` | proof as above | 202 `{scheduled_for}` (30-day grace; refresh + push tokens revoked, current access tokens blocked, email sent) |
| `DELETE /privacy/deletion-request` | — (sign in during grace) | 204 cancelled |

### 2.14 Support

| Method & path | Request | Response |
|---|---|---|
| `GET /support/faqs` | `q?: SafeSearchQuery` | `{items:[{id, question, answer}], contact:{email, email_response, phone (STAR only), phone_hours, phone_requires_star}}` (S14; FAQ text is a draft for owner review) |
| `POST /support/tickets` | multipart: `category: app_crash|data_sync|billing|device_link|account|other`, `description: SafeText(2000)`, `screenshot?` (PNG/JPEG magic bytes, ≤ 10 MB, filename `SafeFileName`, re-encoded, EXIF stripped) | 201 `{ticket_ref: NC-XXXXXXXX}` · 5 / 24 h (429 `SUPPORT_LIMIT_REACHED`); 422 `UPLOAD_INVALID`; forwarded to `SUPPORT_INBOX_ADDRESS` as plain text by the worker |
| `POST /support/feature-requests` | `title: SafeShortText(120)`, `benefit: SafeText(1000)` | 201 `{request_id}` · 5 / 24 h |

### 2.15 Sync and health

| Method & path | Auth | Response |
|---|---|---|
| `GET /sync/changes?since=<cursor>` | User | `{meals, intakes, workouts, sleep_entries, deleted_ids, next_cursor, has_more}` (≤ 500 per page; entries of the last 8 days; opaque cursor, 422 if it does not parse; S14) |
| `GET /health/live` | Public | `{status:"ok"}` |
| `GET /health/ready` | internal (load balancer only) | DB + Redis check, no details |

### 2.16 Staff (`/admin/*`, IP allow-list + role)

| Method & path | Role | Request |
|---|---|---|
| `POST /admin/foods`, `PATCH /admin/foods/{id}` | nutritionist | `name: SafeShortText(120)`, `category_code`, `basis: g|ml`, `is_cooked`, `source_ref: SafeShortText(120)`, 17 nutrients (`condecimal ≥ 0`, unit-specific max), `aliases: list[SafeShortText(60)]` |
| `GET /admin/support/tickets` | support | (decrypted description; access audited) |
| `PUT /admin/feature-flags/{key}` | admin | `enabled: bool` |

---

## 3. Tier enforcement matrix (server)

| Feature code | Endpoints | STANDARD | STAR |
|---|---|---|---|
| `nutrients_17` | daily-summary, foods/{id}, breakdown | 6 fields + `locked_nutrients_count: 11` | 17 |
| `meal_logs_per_day` | POST /meals | 4 | 8 |
| `voice_logging`, `barcode_logging` | voice/parse, foods/barcode, POST /meals source | 403 | ✓ |
| `meal_breakdown` | /meals/{id}/breakdown | 403 | ✓ |
| `advanced_hydration` | temperature, workouts, status computation | 25 °C, no workouts | ✓ |
| `premium_drinks`, `custom_drinks` | intakes, custom-drinks | 403 | ✓ |
| `sleep` | /sleep/*, sleep shares | 403 | ✓ |
| `rin_ai` | /rin/*, custom-drinks/estimate | 403 | ✓ + daily tokens |
| `custom_report`, `report_insights` | POST /reports | monthly only | ✓ |

Entitlement = highest of (active/grace store subscription, active entitlement grant). Computed by `billing.fn_current_entitlement(user_id)`, cached in Redis 60 s and invalidated on billing events.
