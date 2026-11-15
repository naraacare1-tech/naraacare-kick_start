# Session 10 — Sleep Avatar (STAR) (DB → API → App)

## Goal and scope
Deliver the STAR-only Sleep avatar: sleep/wake entry with night wakings, multiple entries per day, counted duration with buffers, goal by age (editable), score and label, Today's Sleep, Update Sleep, Info, edit last 2, blurred upsell for STANDARD.

**In:** `sleep.*` functions/procedures, `/sleep/*`, `/me/sleep-goal`, mobile `features/sleep`.
**Out:** sharing sleep in circles (S12), sleep in reports (S14), wearable sync (post-MVP).

## Prerequisites
S02–S09 (entitlement checks from S05; S11 is not required — test with a seeded entitlement grant). **Blocking decision: OQ-23.**

## Files to create / modify

### naraacare-database
```
functions/R__20_sleep.fn_summary_by_date.sql fn_entries_by_date.sql
procedures/R__30_sleep.pr_log_entry.sql          # STAR check (billing.fn_current_entitlement), overlap via exclusion constraint, wakings, counted_min, daily_summary upsert, activity day, feed event
procedures/R__30_sleep.pr_update_entry.sql pr_delete_entry.sql   # last-2, 7 days, If-Match
procedures/R__30_app.pr_set_sleep_goal.sql
tests/400_sleep.sql
```

### naraacare-backend
```
app/domain/sleep/calculator.py      # counted minutes, score, label, default goal by age
app/api/v1/routers/sleep.py  app/schemas/sleep.py  app/repositories/sleep_repo.py
tests/unit/domain/sleep/test_calculator.py  tests/integration/test_sleep.py
```

### naraacare-mobile
```
lib/features/sleep/presentation/screens/{sleep_avatar_card, sleep_locked_card, todays_sleep, update_sleep, sleep_info}.dart
lib/features/sleep/presentation/widgets/{time_wheel_ampm, waking_row, score_badge}.dart
test/features/sleep/**
```

## Step-by-step tasks
1. Calculator (doc 06 §4): buffers +15/−15, wakings +10 each, clamp ≥ 0, sum per wake local date, score = min(100, round(total/goal × 100)), label thresholds.
2. Validation: wake > start, ≤ 16 h, wake ≤ now + 5 min, wakings inside the interval, ordered, ≤ 10; no overlap with other entries (DB exclusion → 409 `SLEEP_OVERLAP`).
3. Endpoints; tier enforcement (403 `UPGRADE_REQUIRED`).
4. App: STANDARD sees a blurred avatar card "Unlock your Sleep Avatar" → upsell; STAR sees duration + score; tap → Today's Sleep (start, wake, goal, achieved, score + label, explanation); Update Sleep with am/pm wheels and "Add night waking"; edit last 2; Info (copy updated to explain buffers per OQ-23).
5. Default goal shown from age; editable in Today's Sleep → `PUT /me/sleep-goal`.
6. Offline entry support via outbox.

## DB objects
Functions/procedures above.

## API endpoints
`POST /sleep/entries`, `PUT /sleep/entries/{id}`, `DELETE /sleep/entries/{id}`, `GET /sleep/summary`, `PUT /me/sleep-goal`.

## Screens (Figma frames)
Sleep avatar (STAR), "Free plan – Sleep avatar blurred / Unlock your Sleep Avatar", `Today's Sleep`, `Update Sleep`, Sleep `Information`, Android sample look.

## Security checks
Server-side STAR gate on every sleep endpoint; IDOR; edit window; overlap protection; no health values in notifications ("Remember to log your sleep").

## Input-validation checklist
- [ ] No free-text fields; times via wheels; API uses `datetime` types with range validation; goal `conint(240..720)`.
- [ ] Payload sweep confirms no string fields were introduced (or covers any that were).

## Tests to write
DOC example 450 min / 94 %; FIG 7h45 → 97 %; one waking → 420 min / 88 %; boundaries (exactly 16 h ok, 16 h 1 min rejected; buffers exceeding duration → 0); multiple entries summed (nap); overlap rejected; STANDARD 403; last-2 edit; timezone (entry crossing midnight belongs to wake date); widget tests (locked vs unlocked, wheels, waking rows).

## Acceptance criteria / Definition of done
- [ ] Calculations match doc 06 §4 examples.
- [ ] STANDARD cannot read or write sleep via API (403) and sees the blurred upsell.
- [ ] Overlapping entries are impossible (DB-enforced).
- [ ] Screens match Figma on both platforms.

## Estimated effort
4–5 developer-days.

## Implementation status (2026-11-02)

Built locally; nothing is committed. Tests are deferred (owner decision, 2026-11-02); the list is in `docs/pending-tasks.md`.

| Acceptance criterion | Status |
|---|---|
| Calculations match doc 06 §4 examples | ✅ checked once by hand on the migrated database: 23:00–07:00 → 450 min, 94 % Good; with a 02:00–02:20 waking → 420 min, 88 % Fair (test files deferred) |
| STANDARD cannot read or write sleep via API (403) and sees the blurred upsell | ✅ every sleep routine checks the `sleep` entitlement in the database, the API checks it first (403 `UPGRADE_REQUIRED` with `feature: sleep`); the app shows the blurred "Unlock your Sleep Avatar" card for STANDARD |
| Overlapping entries impossible (DB-enforced) | ✅ the S02 exclusion constraint; the procedures report it as 409 `SLEEP_OVERLAP` |
| Screens match Figma on both platforms | ⚠️ built from the App Design structure and doc 02; pixel review blocked by the Figma MCP limit (as S07) |

**Database:** `V019` (CREATE on `sleep` for `api_definer`); `sleep.fn_summary`, `pr_log_entry`, `pr_update_entry`, `pr_delete_entry`, `app.pr_set_sleep_goal`; internal `sleep.fn_constants`, `fn_counted_min`, `fn_editable_entry_ids`, `fn_require_sleep`, `fn_validate_entry`, `fn_lock_editable_entry`, `pr_refresh_daily_summary`. Existing 20 pgTAP files still green, no drift, sqlfluff clean.

**Backend:** `GET /sleep/summary`, `POST/PUT/DELETE /sleep/entries`, `PUT /me/sleep-goal` (`app/domain/sleep/service.py`, `app/repositories/sleep_repo.py`, `app/schemas/sleep.py`); new error `SLEEP_OVERLAP` (409). Tracking services moved from `_init_auth` into `_init_tracking`. ruff and mypy strict clean.

**Mobile:** `features/sleep`: Sleep card (STAR) and blurred locked card (STANDARD → upsell), Today's Sleep (entries, total vs goal, score and label, buffer explanation, goal wheel 4–12 h in 15-minute steps), Update Sleep (bedtime and wake time on wheels, up to 10 night wakings, edit/delete of the last 2), Info (counting rules per OQ-23), offline queue and cached summary. `flutter analyze --fatal-infos` clean.

**Decisions and deviations** (doc 04 updated):
- **Sleep maths live in the database** (`sleep.fn_counted_min` with the calc constants, daily score in `pr_refresh_daily_summary`), like nutrient maths in S08, instead of a backend `calculator.py`: one place computes and snapshots `counted_min`, so the API, app, reports (S14) and circle shares (S12) all read the same numbers. The buffers used are stored with each entry.
- **`PUT /me/sleep-goal` works on every tier** (profile data); reading and logging sleep need STAR. Changing the goal rescores today only.
- **`GET /sleep/summary`** returns `label` (`good|fair|low|none`) and the `buffers` in force for the explanation text, plus each entry's `version`, `editable` flag and wakings.
- No free-text fields: times come from wheels, the goal from a wheel.

**Open:** Figma pixel review; deferred tests (`docs/pending-tasks.md`).

