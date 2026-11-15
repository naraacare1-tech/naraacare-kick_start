# 06 — Business Rules and Calculations

Source of truth: **NaraaCare MVP.docx** (DOC). Every number here was re-computed in Python and matches the DOC examples. Product-defined constants (not from published research) are marked **[product]** and need expert review (DOC "What is science, and what is our choice?", OQ-12).

All constants live in `ref.calc_constant` under a `calc_version` (initial `2026.1`). Code reads constants by version; it never hard-codes them. Each daily snapshot/summary records its `calc_version`, so past days stay reproducible after constants change.

Implementation: `naraacare-backend/app/domain/{nutrition,hydration,sleep}/calculator.py`. These are pure functions (no I/O), with `Decimal` for nutrition and `float` for hydration, and are unit-tested against every example in this document.

---

## 1. Shared rules

| Rule | Value | Source |
|---|---|---|
| Unit storage | metric; convert only for display (1 in = 2.54 cm, 1 lb = 0.45359237 kg, °F = °C × 9/5 + 32) | DOC §3 |
| Age | `age = age_years + full years since age_recorded_on` (no DOB stored) | OQ-31 |
| Adults only | 18 ≤ age ≤ 100 | DOC §3 |
| Valid input ranges | height 120–230 cm · weight 30–250 kg · temperature 15–40 °C · workout 1–600 min · single drink 1–3000 mL | DOC ("reject invalid inputs"), DOC Hydration Step 1 |
| Recalculation | editing profile recalculates **today's** targets (new `health_target_snapshot` for today); past days unchanged | DOC §4a |
| Edit window | only the last 2 entries per avatar, within 7 days | DOC §4, OQ-53 |
| Day | local calendar date in the user's timezone (stored at write time) | OQ-22 |

---

## 2. Nutrition (Energy Avatar)

Execution order (DOC): BMR → TDEE → BMI guardrails → goal adjustment → safety floor → macros → exercise → avatar state.
Rounding: **round half-up to an integer after each step** (reproduces the DOC examples exactly; OQ-21).

### 2.1 Step 1 — BMR (Mifflin-St Jeor)
```
male:   BMR = 10 × weight_kg + 6.25 × height_cm − 5 × age + 5
female: BMR = 10 × weight_kg + 6.25 × height_cm − 5 × age − 161
```
(The equation objects were empty in DOC, so this is reconstructed from the worked examples — OQ-02.) Invalid inputs (≤ 0, out of range) → 422.

### 2.2 Step 2 — TDEE
`TDEE = BMR × multiplier`

| Activity level (onboarding label → code) | Multiplier [product] |
|---|---|
| Little or no exercise → `sedentary` | 0.75 |
| Walks or light workouts 1–3 days → `lightly_active` | 1.00 |
| Exercise 3–5 days/week → `moderately_active` | 1.02 |
| Exercise most days / physical job → `very_active` | 1.07 |

⚠️ OQ-12: these are far below standard factors; mapping per OQ-13. Planned gym workouts are **not** part of this selection; they are logged separately (Step 7).

### 2.3 Step 3 — BMI guardrails
`BMI = weight_kg / (height_m)²` (shown with 1 decimal).

| Category | BMI | Allowed goals |
|---|---|---|
| Underweight | < 18.5 | Maintain, Mild/Standard/Aggressive Gain (**all loss goals disabled**) |
| Normal | 18.5 ≤ BMI < 25.0 | all except **Aggressive Loss** |
| Overweight / Obese | ≥ 25.0 | all goals |

Boundaries use half-open intervals (DOC "18.5 – 24.9" → `< 25.0`, so 24.95 is Normal). The API rejects a blocked goal (422 `GOAL_NOT_ALLOWED`); the app only lists allowed goals (`GET /me/goal-options`).
Healthy weight range shown on onboarding step 4 = `[18.5 × h², 24.9 × h²]` kg, rounded to integers. A target outside it shows a warning, never a block (OQ-15).

### 2.4 Step 4 — Goal adjustment (7,700 kcal ≈ 1 kg fat)

| Goal code | Rate | Δ kcal/day |
|---|---|---|
| `aggressive_loss` | −1.00 kg/week | −1000 |
| `moderate_loss` | −0.75 | −750 |
| `standard_loss` | −0.50 | −500 |
| `mild_loss` | −0.25 | −250 |
| `maintain` | 0 | 0 |
| `mild_gain` | +0.25 | +250 |
| `standard_gain` | +0.50 | +500 |
| `aggressive_gain` | +0.75 | +750 |

`calculated_daily_target = TDEE + Δ`

### 2.5 Step 5 — Safety floor
```
floor = 1200 (female) | 1500 (male)
base_daily_target = max(calculated_daily_target, floor)
override_flag = calculated_daily_target < floor
```
When `override_flag` is true, the app shows: "We've set your target to a safe minimum."

### 2.6 Step 6 — Macronutrients

| Macro | Share | kcal/g | Grams |
|---|---|---|---|
| Carbohydrates | 55 % | 4 | `base × 0.55 / 4` |
| Fat | 25 % | 9 | `base × 0.25 / 9` |
| Protein | 20 % | 4 | `base × 0.20 / 4` |

The 11 STAR micronutrients, fiber and sugar have **no targets** in DOC. Totals are shown without goals (OQ-11).

### 2.7 Step 7 — Exercise (net intake)
`effective_allowance = base_daily_target + Σ exercise_kcal(today)`
Exercise kcal formula is **not in DOC** (OQ-16). Proposed: `kcal = MET × weight_kg × duration_h`, rounded half-up.

| Workout | MET [proposal] | Sweat mL/kg/h (DOC) |
|---|---|---|
| Walking | 3.5 | 5 |
| Gym | 5.0 | 7.5 |
| Cycling | 7.5 | 10 |
| Swimming | 7.0 | 10 |
| Running | 9.8 | 12.5 |
| Trekking | 6.0 | 15 |

Example: 80 kg, 60 min run → 9.8 × 80 × 1 = **784 kcal**.

### 2.8 Step 8 — Avatar state
`avatar_fill_pct = total_logged_food_kcal / effective_allowance × 100` (1 decimal; the server returns both the value and the state)

| Fill % | State | Asset |
|---|---|---|
| = 0 | `empty` (Empty / Depleted) | low-energy, resting |
| 0 < x < 50 | `fueling` | posture straightening, subtle glow |
| 50 ≤ x < 100 | `energized` (Active / Energized) | strong posture, bright |
| 100 ≤ x ≤ 105 | `goal_met` (Optimal) | gold aura, celebration |
| > 105 | `overfilled` (Heavy) | sluggish posture |

Half-open boundaries close DOC's decimal gaps (49.5 → fueling; 99.9 → energized).

### 2.9 Worked examples (verified)

**Example 1 — moderately active male, standard gain**
Male, 30 y, 180 cm, 70 kg, ×1.02, +500.
BMR = 700 + 1125 − 150 + 5 = **1680** · TDEE = 1680 × 1.02 = 1713.6 → **1714** · BMI = 70 / 1.8² = **21.6** (Normal; gain allowed) · target = 1714 + 500 = **2214** · floor 1500 → no override · carbs 2214×0.55/4 = 304.4 → **304 g** · fat 2214×0.25/9 = 61.5 → **62 g** · protein 2214×0.2/4 = 110.7 → **111 g** · logs 1107 kcal food, 0 exercise → fill = 1107/2214 = **50.0 % → energized**.

**Example 2 — sedentary female, standard loss (safety floor)**
Female, 25 y, 160 cm, 65 kg, ×0.75, −500.
BMR = 650 + 1000 − 125 − 161 = **1364** · TDEE = 1023 · BMI = **25.4** (Overweight; all goals) · target = 523 → **clamped to 1200, override_flag = true** · carbs **165 g**, fat 33.3 → **33 g**, protein **60 g** · workout 200 kcal → allowance **1400** · food 1450 → fill = **103.6 % → goal_met** (DOC shows 103.5 % due to truncation; the API returns 1 decimal, rounded half-up).

### 2.10 Food logging maths (DOC data flow)

1. Every food row stores 17 nutrient values per **100 g** (solids) or **100 ml** (liquids, `basis='ml'`).
2. Portion → amount: `amount = quantity × portion_quantity(unit, size)`, where the portion comes from `nutrition.food_unit_override`, else `ref.food_category_unit`.
3. `multiplier = amount / 100`; each nutrient = `per_100 × multiplier`, kept at 3 decimals in `meal_item` and shown rounded (kcal integer; g 1 decimal; mg/mcg integer).
4. If the food basis and unit basis differ (ml portion on a g-based food), convert with `density_g_per_ml` (default 1.0).

**Example (DOC):** 150 g apple, per 100 g: 52 kcal, 14 g carbs, 4.6 mg vit C → ×1.5 → **78 kcal, 21 g, 6.9 mg**.
**Example (DOC Dal):** 1 medium katori = 150 ml → ×1.5; tbsp 15 ml → ×0.15; small katori 100 ml → ×1.0; large 200 ml → ×2.0; bowl 300 ml → ×3.0.

**Portion defaults (DOC Indian measurement matrix, seeded into `ref.food_category_unit`):**

| Category | Units | Default | Quantity |
|---|---|---|---|
| Dal, sambar, kadhi | katori (S/M/L), bowl, tbsp, cup | 1 medium katori | 150 ml (S 100, L 200, bowl 300, tbsp 15) |
| Dry sabzi / poriyal | katori, tbsp, cup | 1 medium katori | 110 g (DOC 100–120 g; midpoint, confirm) |
| Rice, biryani, pulao | katori, cup, plate (half/full), tbsp | 1 medium katori | 150 g; half plate 200 g; full plate 400 g |
| Roti, chapati, bhakri | piece S/M/L | 1 medium | 40 g (S 30, L 55 — confirm) |
| Naan, kulcha, bhatura | piece, half | 1 piece | 100 g (half 50) |
| Meat, chicken, paneer | piece, katori, cup | 1 piece | 35 g (DOC 30–40) |
| Milk, chaas, juices | glass, cup, mug | 1 glass | 200 ml |
| Tea, coffee | cup, mug, cutting | 1 cup | 150 ml (cutting 75, mug 250 — confirm) |
| Oils, ghee, sugar, seeds | tsp, tbsp | 1 tsp | 5 g/ml (tbsp 15) |
| Whole fruits | piece S/M/L, cup chopped | 1 medium | 150 g |

Raw vs cooked: UI units map to **cooked** entries (DOC).

### 2.11 Meal rules
- Limit: 4 saved meals/day (STANDARD), 8 (STAR), counted from non-deleted meals of the local date (OQ-09). The limit is enforced inside `nutrition.pr_log_meal` under a row lock on the user's `daily_summary` row (prevents a race between two devices).
- Meal type is auto-suggested by local time: 05:00–10:59 breakfast · 11:00–15:59 lunch · 16:00–18:59 snack · 19:00–04:59 dinner. Editable (OQ-18).
- Hydration food credit: the first 3 non-deleted meals of the day get `hydration_credit = true` (see §3.6).
- Daily summary = Σ meal_item snapshots of non-deleted meals (maintained aggregate).

---

## 3. Hydration (Yamada et al. 2022 model)

Full precision internally, rounded only for display (OQ-21). STANDARD vs STAR inputs per OQ-04.

### 3.1 Inputs

| Input | Use | STANDARD | STAR |
|---|---|---|---|
| Sex | lean body weight formula | ✓ | ✓ |
| Height, weight | LBW; weight sets insensible loss and tank size | ✓ | ✓ |
| Age | age effect | ✓ | ✓ |
| Body type | LBW factor | ✓ | ✓ |
| Activity level | activity number | ✓ | ✓ |
| Temperature | temperature effect (default 25 °C; accepted 15–40 °C) | fixed 25 °C | ✓ |
| Workouts | sweat loss | — | ✓ |
| Drinks, meals | fill the tank | ✓ | ✓ |

### 3.2 Lean body weight (Boer 1984) × body-type factor [product]
```
male:   LBW = (0.407 × W + 0.267 × H − 19.2) × body_factor
female: LBW = (0.252 × W + 0.473 × H − 48.3) × body_factor
body_factor: ectomorph 0.97 · mesomorph 1.00 · endomorph 1.03
```

### 3.3 Daily water movement (mL)
```
TWT = 861.9 × activity_number + 37.34 × LBW + athlete_bonus + age_effect + temp_effect − 665.4
age_effect  = 29.42 × age − 0.3625 × age²
temp_effect = 1.937 × T² − 23.15 × T
activity_number: sedentary 1.55 · active 1.85 · athlete 2.20 (athlete_bonus = 699.7, else 0)
```
The age/temperature tables in DOC are samples of these formulas (e.g. age 30 → 556; 25 °C → 632). Always use the formula, never table lookup. −665.4 assumes normal humidity, sea level, India.

### 3.4 Daily water need
```
need_before_workouts = 0.85 × TWT
daily_need = clamp(need_before_workouts + Σ workout_sweat, 1500, 6000)   [limits: product]
workout_sweat = sweat_rate(mL/kg/h) × W × minutes / 60
```
`daily_goal` = `daily_need` *now*; it rises when temperature rises or after a workout.

### 3.5 Losses (drain)
```
sleep_rate_ml_h  = 11 × W / 24                                     [11 mL/kg/day: product]
overnight_loss   = sleep_rate × sleep_hours                         (default 8 h, 23:00–07:00)
awake_rate_ml_h  = (need_before_workouts − overnight_loss) / (24 − sleep_hours)
per_minute       = rate / 60
```
- A workout drains its sweat **immediately** at the time it is logged (DOC: "drops his avatar about 62 % at once").
- A temperature change applies from that moment (piecewise integration); hours already passed keep the old rate.
- Display-only breakdown (Info screen): insensible 11 × W/day; stool 150 mL; everyday sweat 100 mL + heat sweat (temp_effect − 632, only above 25 °C); urine = remainder (min 500 mL).

### 3.6 Fills
- Drink: `effective_ml = volume_ml × hydration_factor`

| Drink | Factor | Tier (OQ-05) |
|---|---|---|
| Water | 1.000 | STANDARD |
| Tea | 0.997 | STANDARD |
| Milk | 0.880 | STANDARD |
| Coconut water | 0.950 | STANDARD |
| Coffee | 0.994 | STAR |
| Orange / other juice | 0.885 | STAR |
| Alcohol (beer etc.) | 0.000 | STAR |
| Custom drink | AI estimate; 0.85 if unsure; user confirms | STAR |

- Swipe up: +100 mL water; swipe down: −100 mL water (an adjustment entry; rejected if the day's water volume would go below 0).
- Food: each meal with `hydration_credit` adds `0.20 × daily_need / 3` (max 3 per day).

### 3.7 Avatar tank
```
balance(t)  = Σ fills since wake − Σ drain since wake − overnight_loss     (starts at −overnight_loss at wake)
balance     = min(balance, +300)                                         (extra-water allowance: product)
tank_ml     = 0.02 × W × 1000                                            (2 % of body weight, ACSM)
level_pct   = clamp(100 × (1 + balance / tank_ml), 0, 100)
left_to_drink = max(0, −balance) + awake_rate × hours_until_bedtime
```

| Level | Band | Copy |
|---|---|---|
| 80 ≤ x ≤ 100 | `well` | Well hydrated |
| 50 ≤ x < 80 | `drink_soon` | Drink soon |
| 20 ≤ x < 50 | `low` | Low |
| x < 20 | `critical` | Critical, drink now |

### 3.8 Headline state (OQ-17)
`effective_intake` = Σ effective_ml of drinks today (food water excluded from the headline, shown separately).

| State | Rule |
|---|---|
| `empty` | effective_intake = 0 → "Let's get started!" |
| `in_progress` | 0 < intake < goal → "{x} L of {goal} L goal", % = intake/goal |
| `goal_completed` | goal ≤ intake ≤ 1.10 × goal [product] |
| `above_goal` | intake > 1.10 × goal → number only + slight warning |
| `day_ending_soon` | intake < goal and now within 3 h of bedtime |
| overhydration caution (flag) | intake > 1.5 × goal or > 6000 mL (OQ-55) |
| temperature nudge (STAR flag) | no temperature set today (OQ-19) |

### 3.9 Worked example — Kompal (DOC, verified)
Woman, 65 kg, 162 cm, 32 y, endomorph, sedentary, 25 °C, no workout.
- LBW = (0.252×65 + 0.473×162 − 48.3) × 1.03 = 44.706 × 1.03 = **46.05 kg**
- TWT = 1335.95 + 1719.39 + 570.24 + 631.88 − 665.4 = **3,592 mL**
- Need = 0.85 × 3592.06 = **3,053 mL**
- Sleep rate 29.79 mL/h × 8 h = **238 mL** overnight · awake rate = (3053.25 − 238.33)/16 = **175.9 mL/h** (2.93 mL/min)
- Meal credit = 0.20 × 3053 / 3 = **204 mL** · tank = **1,300 mL**

| Time | Event | Balance (mL) | Level |
|---|---|---|---|
| 07:00 | wakes | −238.3 | 81.7 % |
| 07:30 | 30 min pass | −326.3 | 74.9 % |
| 07:30 | drinks 100 mL water | −226.3 | 82.6 % |
| 09:30 | 2 h pass (−351.9) | −578.2 | 55.5 % |
| 09:30 | drinks 200 mL | −378.2 | 70.9 % |

Left to drink at 09:30 = 378 + 175.9 × 13.5 h = **2,753 mL**. Without drinking the level falls 175.9/1300 = **13.5 %/h**. At 22 °C need = **2,880 mL**; at 35 °C **3,844 mL**.

### 3.10 Worked example — Sahil (DOC, verified)
Man, 80 kg, 28 y, active (1.85), 30 °C, 60-min run. DOC omits height and body type; **175 cm mesomorph** reproduces DOC exactly.
LBW = 60.09 kg · TWT = 4,761 mL · need before workouts = 4,047 · run sweat = 12.5 × 80 × 1 = 1,000 · **daily need = 5,047 mL** · tank = 1,600 mL → the run drops the level **62.5 %** at once.

### 3.11 STANDARD example
Kompal on STANDARD: identical to §3.9 (she is at 25 °C with no workout). If she sets 35 °C on STANDARD, the request is rejected (403 `UPGRADE_REQUIRED`) and her need stays 3,053 mL.

---

## 4. Sleep (STAR)

Default rules (OQ-23):
```
start_counted = sleep_start + 15 min
end_counted   = wake_time − 15 min
waking_loss   = Σ ((back_asleep_at + 10 min) − woke_at)      for each reported night waking
counted_min   = max(0, end_counted − start_counted − waking_loss)
daily_total   = Σ counted_min of entries whose wake_time local date = day   (naps included)
goal_min      = user setting, default by age: 18–64 → 480, 65+ → 450      [product]
score_pct     = min(100, round_half_up(daily_total / goal_min × 100))
label         = ≥ 90 Good · 70–89 Fair · < 70 Low                         [product]
```
Validation: wake > start; duration ≤ 16 h; no overlapping entries; wakings inside the interval and ordered.

Examples
- DOC: bed 23:00, wake 07:00, no wakings → 23:15–06:45 = **450 min (7 h 30 m)**; goal 480 → **94 % Good**.
- FIG Info: 7 h 45 m counted vs 8 h goal → 96.9 → **97 %** ✓.
- With one waking 02:00–02:20: loss = (02:20 + 10) − 02:00 = 30 min → 420 min → 88 % Fair.

---

## 5. Streak

- A day is **active** if the user logged any hydration, nutrition or sleep data with that `local_date` (FIG rule). Deleted-only days do not count.
- `current_streak` = number of consecutive active days ending today (or ending yesterday, if today has no log yet). If yesterday was inactive and today has no log → 0, and the "Streak Broken" state shows.
- `longest_streak` = max run ever. Calendar: Active day / No Data.
- Milestones notify at 3, 7, 14, 30, 60, 100, 365 days [product].

## 6. Referral (OQ-39 defaults)

- Each user has one code `^[A-Z0-9]{6,12}$` and link `https://<REFERRAL_LINK_DOMAIN>/invite/<CODE>`. Attribution happens at sign-up (code entered or install referrer / deep link) for accounts ≤ 7 days old.
- A referred friend **qualifies** after 30 distinct active days within 60 days of sign-up (email verified, onboarding complete, device installation hash not previously seen, not the referrer).
- When 5 friends qualify, the referrer gets a one-time entitlement grant: 30 days (if STANDARD at grant time) or 50 days (if STAR) of STAR. If the user is currently paying, the grant starts at `current_period_end`.
- Nightly job `referral_tally` updates `active_days` and grants rewards.

## 7. Care Circle rules

- Username required for any social action. Max 50 members per circle (members + pending invites); unlimited circles per user.
- Each member shares ≥ 1 avatar (Create/Accept disabled otherwise). Sleep can be shared only by STAR users and is visible only to STAR viewers; others see "Sleep avatar is available with STAR plan".
- A user who downgrades from STAR: the Sleep share is hidden ("blur") but the share row is kept; it reappears on re-upgrade.
- Changing shares removes past shared data from the feed immediately (fan-out-on-read).
- Notifications: goal completions, joins/leaves, mentions, admin changes. Individual water/meal/sleep logs go to the Recent Updates feed only (DOC §5).
- Admin succession: if the last admin leaves, the earliest-joined active member becomes admin; an empty circle is soft-deleted.
- Blocking: a blocked user cannot find, invite, connect with or mention the blocker; existing shared circles remain, but their messages are hidden for the blocker.

## 8. Rin AI rules (OQ-37 defaults)

- STAR only. Text only. Daily token allowance (input + output + cache-write tokens), reset at local midnight, shown as a percentage. All AI features (chat, drink estimate, voice parse fallback, report insights) draw on it.
- Context sent to the model: the user's own profile summary (age band, sex, goals, targets), today's and the last 7 days' aggregates, the user's memory summary. **Never** other users' data, email or full name.
- Meal/drink logging by chat: the model returns structured items via a tool; the server validates them against the food DB and creates an `ai.pending_action`. Nothing is logged until the user taps **Add to Avatar** (Edit opens the meal editor).
- Guardrails: no diagnosis or medication dosing; symptoms suggesting an emergency (chest pain, fainting, self-harm, severe dehydration signs) → fixed response with India emergency numbers (112; ambulance 108; Tele-MANAS 14416) and a recommendation to seek care. Eating-disorder signals → supportive response, no calorie-cutting advice, and the floor (§2.5) is always respected.
- Every response UI carries the disclaimer; the Help screen repeats it.

## 9. Subscription and entitlement rules

- Tier = STAR if any of: subscription status ∈ {active, in_grace} with `current_period_end > now`, or an entitlement grant covering now. Otherwise STANDARD.
- Cancel = auto-renew off; access continues to period end (DOC §8). Refund/revoke → immediate STANDARD.
- STAR-only historical data after downgrade: kept, hidden in the UI; included in monthly reports for months the user was STAR (OQ-38).

## 10. What the app may compute locally

Only unit conversions, optimistic display of a just-queued entry (adding `effective_ml` to the last server status), and countdown timers. All goals, levels, states and limits come from the server and are refreshed after sync.
