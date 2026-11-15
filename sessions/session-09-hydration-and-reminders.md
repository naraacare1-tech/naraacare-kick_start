# Session 09 — Hydration Tracking, Workouts and Reminders (DB → API → App)

## Goal and scope
Deliver the Hydration avatar: water and drink logging (swipe ±100 mL, presets, other drinks, STAR custom drinks with AI estimate), temperature and workouts (STAR), the tank model and status states, edit last 2, Info, offline logging, workouts feeding nutrition allowance, plus push/local **reminders** infrastructure (devices, preferences, schedules, day-ending-soon nudges).

**In:** `hydration.*`, `activity.*` functions/procedures; `/hydration/*`, `/workouts`, `/devices`, `/me/notification-preferences`, `/me/reminders`; worker reminder jobs; mobile `features/hydration`, notifications permission flow.
**Out:** circle/social notifications (S12), notification centre list UI (S14).

## Prerequisites
S02–S08. **Blocking decisions: OQ-04 (tier split) and OQ-17 (display model).** Also OQ-05, OQ-19, OQ-20, OQ-21, OQ-22, OQ-55, OQ-58. Firebase projects per flavor created.

## Files to create / modify

### naraacare-database
```
functions/R__20_hydration.fn_day_inputs.sql          # profile snapshot, temperature changes, intakes, workouts, meal credits for a local date
functions/R__20_hydration.fn_intakes_by_date.sql fn_drinks_for_user.sql fn_custom_drinks.sql
functions/R__20_activity.fn_workouts_by_date.sql
procedures/R__30_hydration.pr_log_intake.sql         # tier check on drink, swipe −100 rule (day water ≥ 0), snapshot factor, upsert daily_summary, activity day, feed event
procedures/R__30_hydration.pr_update_intake.sql pr_delete_intake.sql   # last-2 + 7-day + If-Match
procedures/R__30_hydration.pr_set_temperature.sql    # STAR only
procedures/R__30_hydration.pr_save_custom_drink.sql  # unique name per user, ≤ 100
procedures/R__30_hydration.pr_upsert_daily_summary.sql  # called by API after status calc (need, goal_completed_at)
procedures/R__30_activity.pr_log_workout.sql pr_delete_workout.sql     # STAR; sweat + kcal snapshot; nutrition daily_summary exercise_kcal/allowance update
procedures/R__30_notify.pr_register_device.sql pr_revoke_device.sql pr_set_preferences.sql pr_set_reminders.sql
functions/R__20_notify.fn_due_reminders.sql          # due in the next minute (UTC), respecting prefs + quiet hours 22:30–07:00 local
tests/300_hydration_*.sql tests/310_activity.sql tests/320_notify.sql
```

### naraacare-backend
```
app/domain/hydration/calculator.py   # (extend) drain integration, workouts, meals, cap +300, level, bands, left_to_drink
app/domain/hydration/status.py       # headline states (doc 06 §3.8), STANDARD vs STAR inputs
app/domain/activity/workouts.py      # sweat + MET kcal
app/api/v1/routers/hydration.py workouts.py devices.py notifications.py (prefs/reminders only)
app/schemas/hydration.py workouts.py devices.py notification_prefs.py
app/integrations/fcm.py              # firebase-admin; generic text, no health values
app/workers/jobs/reminders.py day_ending_soon.py
app/domain/ai/drink_estimator.py     # Claude call (structured output: factor 0–1 + confidence); fallback 0.85; uses Rin allowance (S13 metering stub now)
tests/unit/domain/hydration/test_status.py test_examples.py (Kompal, Sahil timelines)
tests/integration/test_hydration.py test_workouts.py test_reminders.py
```

### naraacare-mobile
```
lib/features/hydration/presentation/screens/{hydration_avatar_card, add_intake_sheet (Water | Other Drinks tabs), edit_entry, temperature_activity_sheet, hydration_info}.dart
lib/features/hydration/presentation/widgets/{swipe_gesture_layer, preset_chips, drink_chips, custom_drink_field, level_ring, temperature_wheel, workout_chips, duration_presets}.dart
lib/features/notifications/data/push_service.dart local_reminders.dart permission_explainer.dart
test/features/hydration/**
```

## Step-by-step tasks
1. Status engine: given day inputs and `at`, integrate balance from wake time: overnight loss at wake; awake drain at the piecewise rate (recompute when temperature changes; STANDARD always 25 °C); workouts subtract sweat at their time (STAR); meals with credit add `0.20 × need / 3`; drinks add effective mL; cap at +300; level/band; headline state; left to drink. Pure function, unit-tested with the doc 06 timelines.
2. `GET /hydration/status` builds inputs via `fn_day_inputs`, returns the status, and upserts `hydration.daily_summary` when `goal_completed_at` first becomes true (also emits a goal-completed event for S12).
3. Intake endpoints with drink tier checks; swipe −100 only for water; validation `volume_ml` 1–3000.
4. STAR: temperature wheel (°C/°F display, stored °C 15–40), workouts (6 types, presets 15/30/45/60 + custom 1–600), custom drinks: estimate via Claude (`drink_estimator`) → user confirms factor → saved for reuse. STANDARD: Temperature & Activity shows upsell (OQ-04).
5. App: swipe-up/down gesture on the avatar (+100/−100 water, haptic feedback, optimistic update); Add Water/Drink sheet (H3/H4) with Recent Updates; edit last 2 (H5); avatar states (0 %, in progress, goal completed, above goal, day ending soon, temperature nudge, overhydration caution); Info (H7) with corrected "swipe" copy and disclaimers.
6. Workouts also update nutrition allowance (`exercise_kcal`) → Energy avatar refresh.
7. Reminders: notification permission explainer → FCM token → `POST /devices`; preferences + reminder schedules; worker `send_reminders` (every minute) and `day_ending_soon` (every 15 min); push texts generic (no values; OQ-41); local notifications as an offline fallback for hydration reminders.
8. Offline: intakes queued; status shows the last server status + pending effective mL (optimistic) until sync.

## DB objects
Functions/procedures above (tables from S02).

## API endpoints
`GET /hydration/drinks`, `POST/PUT/DELETE /hydration/intakes`, `GET /hydration/intakes`, `GET /hydration/status`, `PUT /hydration/temperature`, `POST /hydration/custom-drinks/estimate`, `POST /hydration/custom-drinks`, `POST/GET/DELETE /workouts`, `POST /devices`, `DELETE /devices/{installation_id}`, `GET/PUT /me/notification-preferences`, `GET/PUT /me/reminders`.

## Screens (Figma frames)
`Home/Water` (all state variants on the `Home Page`/`Section 2` boards: 0 %, 84 %, 80 %, Goal Completed, Above Goal, Day ending soon, disabled→nudge), `Water Update 1`, `Water Update 2/Add water`, `Water Update 2/Add other drinks` (+ search, custom "Banana Shake"), Recent Updates/Edit your entry, `Water/Temperature & Gym` (+ Filled), `Water/Info`, `Notification Settings` (reminders part).

## Security checks
Tier enforcement for temperature/workouts/premium & custom drinks (server); LLM call for drink estimate uses only the drink name (no user data) and validates structured output (factor 0–1); push payload privacy (OQ-41); FCM tokens encrypted at rest; device registration bound to user; IDOR on intakes/workouts; edit window server-side; reminder job cannot be triggered by clients.

## Input-validation checklist
| Field | App validator | Max | API type | DB |
|---|---|---|---|---|
| Water amount | `integer(1,3000)` digits only | 4 | conint | CHECK 1–3000 / −100 rule |
| Drink search | `search()` | 64 | SafeSearchQuery | — |
| Custom drink name | `shortText(60)` | 60 | SafeShortText(60) | safe_text(60) + UQ |
| Workout duration | `integer(1,600)` | 3 | conint | CHECK 1–600 |
| Temperature | wheel only (no text) | — | condecimal 15–40 | CHECK 15–40 |
| Reminder times | time picker | — | `time` list ≤ 12 | CHECK cardinality |
| Push token | (system value) | — | SafeDeviceToken | ciphertext |
| App version | (system) | — | SafeAppVersion | CHECK regex |
- [ ] AI-returned explanation text (if displayed) passes SafeShortText before storage/display; otherwise not stored.
- [ ] Payload tests across all three layers updated.

## Tests to write
Kompal timeline exact to 0.1 %; left to drink 2,753; 22/35 °C needs; Sahil 5,047 and −62.5 %; STANDARD ignores temperature/workouts (403 on set); cap +300; level clamps; band boundaries; state rules incl. day-ending-soon window; swipe −100 cannot make the day negative; last-2 edit; tier drink rejection; custom drink uniqueness; reminders due computation across timezones and quiet hours; FCM payload contains no numbers; widget tests for gesture + states; offline replay idempotency.

## Acceptance criteria / Definition of done
- [ ] Status endpoint reproduces every doc 06 §3 example.
- [ ] Headline vs avatar fill behave per the OQ-17 decision; Figma states all reachable.
- [ ] STANDARD/STAR split per OQ-04 enforced server-side.
- [ ] Swipe gesture adds/removes 100 mL with optimistic UI and correct sync.
- [ ] Reminders arrive on Android and iOS test devices at configured times; texts contain no health values.
- [ ] `GET /hydration/status` p95 ≤ 150 ms with 90 days of data.
- [ ] 3-layer payload tests green for new fields.

## Estimated effort
10–11 developer-days.

## Implementation status (2026-11-02)

Built locally; nothing is committed. **Tests from this session onward are deferred (owner decision, 2026-11-02)**: the open test work is listed in `docs/pending-tasks.md`.

| Acceptance criterion | Status |
|---|---|
| Status endpoint reproduces every doc 06 §3 example | ✅ pure engine `app/domain/hydration/status.py`: Kompal timeline (81.7 / 74.9 / 82.6 / 55.5 / 70.9 %), left to drink 2,753 mL, 13.5 %/h, 22 °C 2,880 / 35 °C 3,844 mL, Sahil 5,047 mL and the 62.5 % drop (unit tests) |
| Headline vs avatar fill per OQ-17; Figma states reachable | ✅ headline = drink intake vs goal (empty, in progress, goal completed ≤ 110 %, above goal, day ending soon); ring = tank level with bands; overhydration caution and temperature nudge flags |
| STANDARD/STAR split per OQ-04, server-side | ✅ API and database both check `advanced_hydration`, `premium_drinks`, `custom_drinks`; STANDARD is computed at 25 °C with no workouts (STAR rows kept after a downgrade are ignored) |
| Swipe gesture ±100 mL, optimistic UI, correct sync | ✅ built (vertical swipe on the Water card, haptics, offline queue with the same client id, queued mL added to the last status). Widget tests deferred |
| Reminders arrive on Android/iOS; no health values | ⚠️ server side done (schedules, quiet hours, worker jobs, FCM HTTP v1, fixed generic texts). Device delivery waits for the Firebase projects per flavor (owner action) and the app's Firebase push implementation |
| `GET /hydration/status` p95 ≤ 150 ms with 90 days of data | ⏳ deferred (performance test) |
| 3-layer payload tests for new fields | ⚠️ database payload tests for custom drink names done (pgTAP); API sweep run and mobile payload widget tests deferred |

**Database:** `V018` (CREATE on `hydration`, `activity`, `notify` for `api_definer`); `hydration.fn_day_inputs`, `fn_intakes`, `fn_drinks_for_user`, `pr_log_intake`, `pr_update_intake`, `pr_delete_intake`, `pr_set_temperature`, `pr_save_custom_drink`, `pr_upsert_daily_summary`; `activity.fn_workouts`, `pr_log_workout`, `pr_delete_workout` (rebuild nutrition `exercise_kcal`/allowance and hydration sweat in the same transaction); `notify.pr_register_device`, `pr_revoke_device`, `fn_notification_preferences`, `pr_set_notification_preferences`, `fn_reminders`, `pr_set_reminders`; worker-only `ops.fn_due_reminders`, `ops.fn_day_ending_soon`, `ops.pr_revoke_push_token`. pgTAP `300_hydration`, `310_activity`, `320_notify` (592 assertions); all 20 files green, no drift. sqlfluff clean for the whole repo (Session 08 SQL fixed too; `tests/.sqlfluff` relaxes alias/layout rules for pgTAP files only).

**Backend:** `/hydration/status|drinks|intakes|temperature|custom-drinks(/estimate)`, `/workouts`, `/devices`, `/me/notification-preferences`, `/me/reminders`; `app/integrations/fcm.py`; `app/domain/ai/drink_estimator.py`; worker jobs `notify.send_reminders` (every minute) and `notify.day_ending_soon` (every 15 min). ruff and mypy strict clean. Written before the deferral: unit tests (engine, FCM, estimator, fan-out, schemas) and 9 database integration tests, all green.

**Mobile:** `features/hydration` (Water card with swipe, details, Add Water / Other Drinks sheet with presets, typed amount, drink search, STAR custom drink with estimate and confirmation; Recent Updates with edit/delete of the last 2; Temperature & Activity sheet with wheel and workouts, STAR upsell for STANDARD; Info with the corrected swipe copy); `features/notifications` (permission explainer, Notification Settings with the 12 toggles and reminder times via the system time picker, `PushService` interface). Log Out now revokes the device first. `flutter analyze --fatal-infos` and `dart format` clean.

**Decisions and deviations** (docs 00, 03, 04, 08 updated):
- **FCM over the HTTP v1 API** with the existing HTTP client and PyJWT instead of firebase-admin: same OAuth service-account flow, without the gRPC/Google Cloud dependency tree (smaller install and audit surface). New settings `FCM_API_BASE_URL`, `GOOGLE_OAUTH_TOKEN_URL` (https only); outside dev `FCM_SERVICE_ACCOUNT_JSON` must be a real service-account key. Only an `UNREGISTERED` answer wipes a token.
- **Drink estimate:** Claude (`RIN_MODEL`, low effort) with structured output (factor 0–1, closed confidence and explanation codes); only the drink name is sent, and only with AI consent (otherwise the 0.85 default with `ai_consent_missing`). Nothing free-form from the model is stored or shown. Rin allowance metering arrives in S13.
- **Reminders are opt-in:** schedules never saved come back disabled with suggested times; quiet hours 22:30–07:00 local; hydration reminders stop once the day's goal is completed. Worker functions live in `ops` (owner-run allow-list) because they cross users; the worker's `DATABASE_URL` uses the `app_worker` login.
- **API shape changes to doc 04:** `GET /hydration/status` takes `date?` (past day = end-of-day status) instead of `at?`; `PUT /me/reminders` body is `{reminders: [...]}`; new errors `WATER_BELOW_ZERO` (422) and `CUSTOM_DRINK_LIMIT` (403); custom drink names are unique per user (409 `ALREADY_EXISTS`).
- **Push on mobile** is behind `PushService` (`DisabledPushService` until Firebase exists); `firebase_messaging` / `flutter_local_notifications` (doc 03 pins) and the Android 13 notification permission are added with the Firebase projects. The local offline reminder fallback comes with them.

**Open:** Firebase projects and keys (owner); push implementation in the app; OQ-70 (push text localisation), OQ-71 (reminder defaults and quiet hours sign-off); all deferred tests (`docs/pending-tasks.md`).

