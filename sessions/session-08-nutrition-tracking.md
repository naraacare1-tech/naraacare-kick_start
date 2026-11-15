# Session 08 — Nutrition Tracking (DB → API → App)

## Goal and scope
Deliver the Energy (Nutrition) avatar end to end: food search with Hinglish aliases, portions in Indian units, Add Meal with multiple items, Save Meal with meal-type chip, Nutrition Summary, Today's Nutrition (6 vs 17 nutrients), recent/saved meals, edit/delete last 2, meal limits 4/8, STAR voice + barcode logging, STAR meal-by-meal breakdown, avatar fill/state, offline logging.

**In:** `nutrition.*` functions/procedures, `/foods/*`, `/meals/*`, `/nutrition/*`, `/saved-meals`, admin food endpoints, mobile `features/nutrition`.
**Out:** workouts' kcal (added in S09 together with hydration workouts; the allowance formula already supports it), custom goal profiles (post-MVP).

## Prerequisites
S02–S07. Decisions/defaults: OQ-02, OQ-08, OQ-09, OQ-11, OQ-16, OQ-18, OQ-21, OQ-42 (licensing can trail but must be cleared before launch), OQ-43, OQ-44, OQ-53. Nutritionist delivers the initial food DB CSV (with `source_ref`).

## Files to create / modify

### naraacare-database
```
functions/R__20_nutrition.fn_search_foods.sql        # trigram + alias + tsvector rank; status='active'; limit ≤ 25
functions/R__20_nutrition.fn_food_detail.sql         # food + portions (override → category default)
functions/R__20_nutrition.fn_food_portions.sql       # batch for many food_ids
functions/R__20_nutrition.fn_daily_summary.sql       # one row (+ target, allowance, meal_count)
functions/R__20_nutrition.fn_meals_by_date.sql fn_recent_meals.sql fn_meal_breakdown.sql fn_saved_meals.sql
functions/R__20_nutrition.fn_barcode_lookup.sql fn_alias_match.sql (voice parse)
procedures/R__30_nutrition.pr_log_meal.sql           # lock daily_summary row (upsert + FOR UPDATE), check limit, insert meal+items (snapshots),
                                                     # assign hydration_credit (first 3), upsert summary, mark activity day, emit social.activity_event (if table exists)
procedures/R__30_nutrition.pr_update_meal.sql        # If-Match version, last-2 + 7-day rule, recompute summary delta
procedures/R__30_nutrition.pr_delete_meal.sql        # soft delete, recompute summary, reassign hydration credits
procedures/R__30_nutrition.pr_save_meal_template.sql pr_delete_saved_meal.sql
procedures/R__30_nutrition.pr_admin_upsert_food.sql (role check)
procedures/R__30_nutrition.pr_upsert_barcode_product.sql
tools/import_food_csv.py                              # validated import (Safe rules + numeric ranges) → pr_admin_upsert_food
tests/200_nutrition_*.sql
```

### naraacare-backend
```
app/api/v1/routers/foods.py meals.py nutrition.py admin_foods.py
app/schemas/foods.py meals.py nutrition.py admin_foods.py
app/domain/nutrition/portions.py          # amount = qty × portion; ml↔g density
app/domain/nutrition/nutrients.py         # 17-field scaling; tier filter; rounding for display
app/domain/nutrition/avatar.py            # fill % + state (doc 06 §2.8)
app/domain/nutrition/voice_parser.py      # tokenise transcript; quantity words (ek/do/teen/aadha/1/2…); unit words (katori/bowl/roti/piece/glass…); alias match; returns candidates
app/domain/nutrition/meal_type.py         # time-of-day suggestion
app/integrations/open_food_facts.py       # barcode fallback (timeout 3 s; response validated; cache to barcode_product)
app/repositories/nutrition_repo.py
tests/unit/domain/nutrition/test_portions.py test_avatar.py test_voice_parser.py
tests/integration/test_meals.py test_food_search.py test_tier_nutrition.py
```

### naraacare-mobile
```
lib/features/nutrition/data/... domain/... presentation/screens/
  {nutrition_avatar_card, todays_nutrition_sheet, add_meal, food_search, voice_logging, barcode_scan,
   nutrition_summary, save_meal_sheet, recent_updates, edit_entry, request_food, request_food_thanks, nutrition_info}.dart
lib/features/nutrition/presentation/widgets/{food_item_row, quantity_stepper, unit_dropdown, nutrient_list, upsell_card, meal_type_chip}.dart
test/features/nutrition/**
```

## Step-by-step tasks
1. Import the food DB (CSV → validated → procedures); seed aliases (Hinglish/Hindi), category portions (doc 06 §2.10), overrides.
2. Search: debounce 300 ms, min 1 char, results with default portion and kcal; offline: search the cached recent foods only.
3. Add Meal: items list (qty stepper 0.25 steps, unit dropdown per food), View Nutrition Summary (computed by the server via `POST /meals?dry_run=true`, which validates and returns totals without saving or counting toward the limit, so no nutrition maths runs in the app), Save Meal with meal-type chip, Update Meal for edits.
4. Today's Nutrition sheet (N2): calories with goal (`1450 / 2000 kcal`) + 5 nutrients for STANDARD + upsell "Unlock STAR · 11 more nutrients"; 17 for STAR; "Last updated" time.
5. Avatar card (N1): fill % → state asset; Add Food button; Share/Info.
6. Recent Updates / Saved Meals / Last 2 Updates (N9) with edit (N10) honouring `editable` flags from server.
7. Limit handling: on `DAILY_LIMIT_REACHED` show a sheet with the limit and the STAR upsell (STANDARD) or a friendly message (STAR).
8. STAR voice (N5): `speech_to_text` locale `en-IN` (on-device when supported), transcript → `/nutrition/voice/parse` → editable candidate list → add to meal. STANDARD tapping mic → upsell.
9. STAR barcode (N6): `mobile_scanner` → `/foods/barcode/{code}` → item found card → Add to Meal / Scan Another; not found → manual search (Request New Food removed, OQ-63).
10. Meal-by-meal breakdown (STAR) in Nutrition Summary per meal.
11. Offline: meals created offline go to the outbox with `client_entry_id`; the avatar shows an optimistic state flagged "syncing".
12. Admin endpoints for nutritionists + import tool.

## DB objects
Functions/procedures listed; no new tables (S02 created them).

## API endpoints
`GET /foods/search`, `GET /foods/{food_id}`, `GET /foods/barcode/{code}`, `POST /nutrition/voice/parse`, `POST /meals` (+ `?dry_run=true` preview), `PUT /meals/{id}`, `DELETE /meals/{id}`, `GET /meals`, `GET /meals/recent`, `GET /meals/{id}/breakdown`, `GET /nutrition/daily-summary`, `GET/POST/DELETE /saved-meals`, `POST/PATCH /admin/foods`.

## Screens (Figma frames)
`Home/Nutrition`, `On press`, `Premium plan features`, `Nutrition Update-2` (Add Meal), `Home/Search`, `Nutrition Update` (voice), `Nutrition Update-1` (barcode), `Nutrition Update-3` (summary + Unlock STAR), `Save Meal`, `Nutrition Update/Recent`, `Nutrition/Edit` + thanks, `Nutrition/Info`.

## Security checks
Tier enforcement server-side (source voice/barcode, 17 nutrients, breakdown); limit enforced in procedure under lock (race-proof); IDOR on meals/saved meals; user_id never in payload (fixes DOC sample); Open Food Facts response validated (API10) and no user-supplied URLs (SSRF); admin endpoints role + IP allow-list + audit; edit window server-enforced.

## Input-validation checklist
| Field | App validator | Max | API type | DB |
|---|---|---|---|---|
| Food search | `search()` | 64 | SafeSearchQuery | — |
| Quantity | `decimal(0.25,20,2)` | 5 | condecimal | CHECK 0.25–20 |
| Voice transcript (STT) | `freeText(300)` | 300 | SafeText(300) | not stored |
| Manual barcode / product | `barcodeOrSearch()` | 64 | SafeBarcode / SafeSearchQuery | CHECK regex |
| Saved meal name | `shortText(60)` | 60 | SafeShortText(60) | safe_text(60) |
| Admin food name / alias / source | — (admin API) | 120/60/120 | SafeShortText | safe_text |
- [ ] All covered by backend payload sweep, Flutter widget payload tests, pgTAP payload tests.
- [ ] OFF product names are validated with SafeShortText before storage (rejects → stored as "Unnamed product").

## Tests to write
Portions (dal 0.15–3.0, rice plate 400 g, roti 40 g, ml→g density); apple example; summary totals equal Σ items; limit 4/8 including concurrent requests (two parallel POSTs at 3/4 → exactly one succeeds); last-2 edit rule; 7-day backdating rule; deleting a meal reassigns hydration credits; tier filtering (6 vs 17); voice parser ("do roti aur ek katori dal" → Roti ×2 medium, Dal ×1 medium katori); barcode found / OFF fallback / not found; IDOR; payload sweep; widget tests per screen; offline create → sync once.

## Acceptance criteria / Definition of done
- [ ] Logging a 150 g apple returns 78 kcal / 21 g carbs / 6.9 mg vit C; Example 1/2 avatar states reproduce.
- [ ] STANDARD sees exactly 6 nutrients + locked count 11; STAR sees 17.
- [ ] 5th meal for STANDARD → `DAILY_LIMIT_REACHED`; race test passes.
- [ ] Only the last 2 meals are editable; server rejects older edits.
- [ ] Voice and barcode return 403 `UPGRADE_REQUIRED` for STANDARD.
- [ ] Search p95 ≤ 200 ms on a 10k-food DB.
- [ ] All new fields pass the 3-layer payload tests.

## Estimated effort
10–12 developer-days (DB 2, backend 4, mobile 5, nutritionist data prep in parallel).
