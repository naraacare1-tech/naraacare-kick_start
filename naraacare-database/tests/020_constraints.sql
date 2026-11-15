-- CHECK / FK / exclusion constraints at their boundaries (doc 05 section 5, doc 06 section 1).
BEGIN;
SELECT no_plan();

-- Fixture user (superuser session: RLS does not apply here)
INSERT INTO auth.user_account (id, email, status)
VALUES ('0192f000-0000-7000-8000-0000000000a1', 'u01@example.test', 'active');

-- ---------------------------------------------------------------- profile ranges
SELECT lives_ok(
    $$INSERT INTO app.user_profile (user_id, age_years, age_recorded_on, height_cm, weight_kg)
                  VALUES ('0192f000-0000-7000-8000-0000000000a1', 18, current_date, 120, 30)$$,
    'profile accepts lower boundaries (age 18, 120 cm, 30 kg)'
);
SELECT throws_ok(
    $$UPDATE app.user_profile SET age_years = 17 WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23514', NULL, 'age 17 rejected (18+ only)'
);
SELECT throws_ok(
    $$UPDATE app.user_profile SET age_years = 101 WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23514', NULL, 'age 101 rejected'
);
SELECT lives_ok($$UPDATE app.user_profile SET age_years = 100, height_cm = 230, weight_kg = 250
                  WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$, 'upper boundaries accepted');
SELECT throws_ok(
    $$UPDATE app.user_profile SET height_cm = 119.9 WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23514', NULL, 'height 119.9 cm rejected'
);
SELECT throws_ok(
    $$UPDATE app.user_profile SET weight_kg = 250.01 WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23514', NULL, 'weight 250.01 kg rejected'
);
SELECT throws_ok(
    $$UPDATE app.user_profile SET age_recorded_on = NULL WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23514', NULL, 'age without age_recorded_on rejected'
);
SELECT throws_ok(
    $$UPDATE app.user_profile SET weight_goal_code = 'crash_diet' WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23503', NULL, 'unknown weight goal rejected by FK'
);
SELECT throws_ok(
    $$UPDATE app.user_profile SET timezone = 'Mars/Olympus Mons' WHERE user_id = '0192f000-0000-7000-8000-0000000000a1'$$,
    '23514', NULL, 'malformed timezone rejected'
);

-- ---------------------------------------------------------------- username domain
SELECT lives_ok($$SELECT 'sahil.123'::common.username$$, 'username sahil.123 accepted');
SELECT lives_ok($$SELECT 'aara_sharma12'::common.username$$, 'username aara_sharma12 accepted');
SELECT throws_ok($$SELECT 'ab'::common.username$$, '23514', NULL, 'username shorter than 3 rejected');
SELECT throws_ok($$SELECT 'Sahil'::common.username$$, '23514', NULL, 'upper-case username rejected');
SELECT throws_ok($$SELECT 'a..b'::common.username$$, '23514', NULL, 'consecutive dots rejected');
SELECT throws_ok($$SELECT '.sahil'::common.username$$, '23514', NULL, 'leading dot rejected');
SELECT throws_ok($$SELECT 'sahil-1'::common.username$$, '23514', NULL, 'hyphen rejected');

-- ---------------------------------------------------------------- other domains
SELECT throws_ok($$SELECT 'not-a-hash'::common.argon2_hash$$, '23514', NULL, 'non-Argon2id hash rejected');
SELECT lives_ok(
    $$SELECT '$argon2id$v=19$m=65536,t=3,p=2$c29tZXNhbHQ$aGFzaGhhc2hoYXNo'::common.argon2_hash$$,
    'Argon2id hash accepted'
);
SELECT throws_ok($$SELECT decode('00', 'hex')::common.blind_index$$, '23514', NULL, 'short token digest rejected');
SELECT throws_ok($$SELECT 'Someone@Example.test'::common.email$$, '23514', NULL, 'email must be lower case');
SELECT throws_ok($$SELECT 'a<b>@example.test'::common.email$$, '23514', NULL, 'markup in an email rejected');
SELECT throws_ok($$SELECT '12345a'::common.otp_code$$, '23514', NULL, 'OTP must be 6 digits');
SELECT throws_ok($$SELECT 'tok<script>'::common.opaque_token$$, '23514', NULL, 'markup in a token rejected');
SELECT throws_ok($$SELECT 'javascript://x'::common.https_url$$, '23514', NULL, 'non-https URL rejected');
SELECT throws_ok($$SELECT 'Code1'::common.code$$, '23514', NULL, 'upper-case code rejected');

-- ---------------------------------------------------------------- hydration intake
SELECT lives_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                  VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'water', 1, 1, 1, 'manual')$$,
    '1 mL accepted'
);
SELECT lives_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                  VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'milk', 3000, 0.88, 2640, 'manual')$$,
    '3000 mL accepted with factor snapshot'
);
SELECT throws_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'water', 0, 1, 0, 'manual')$$,
    '23514', NULL, '0 mL rejected'
);
SELECT throws_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'water', 3001, 1, 3001, 'manual')$$,
    '23514', NULL, '3001 mL rejected'
);
SELECT lives_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                  VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'water', -100, 1, -100, 'swipe')$$,
    'swipe-down -100 mL water accepted'
);
SELECT throws_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'water', -100, 1, -100, 'manual')$$,
    '23514', NULL, '-100 mL only allowed for swipe'
);
SELECT throws_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'milk', 200, 0.88, 200, 'manual')$$,
    '23514', NULL, 'effective_ml must equal volume x factor'
);
SELECT throws_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, volume_ml, hydration_factor, effective_ml, source)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 200, 1, 200, 'manual')$$,
    '23514', NULL, 'intake needs exactly one of drink_code / custom_drink_id'
);

-- ---------------------------------------------------------------- temperature
SELECT throws_ok(
    $$INSERT INTO hydration.temperature_log (user_id, temperature_c, effective_from, local_date)
                   VALUES ('0192f000-0000-7000-8000-0000000000a1', 14.9, now(), current_date)$$,
    '23514', NULL, '14.9 C rejected'
);
SELECT lives_ok(
    $$INSERT INTO hydration.temperature_log (user_id, temperature_c, effective_from, local_date)
                  VALUES ('0192f000-0000-7000-8000-0000000000a1', 15, now(), current_date),
                         ('0192f000-0000-7000-8000-0000000000a1', 40, now(), current_date)$$,
    '15 C and 40 C accepted'
);
SELECT throws_ok(
    $$INSERT INTO hydration.temperature_log (user_id, temperature_c, effective_from, local_date)
                   VALUES ('0192f000-0000-7000-8000-0000000000a1', 40.1, now(), current_date)$$,
    '23514', NULL, '40.1 C rejected'
);

-- ---------------------------------------------------------------- workouts
SELECT throws_ok(
    $$INSERT INTO activity.workout (id, performed_at, user_id, local_date, workout_type, duration_min, sweat_ml, kcal, calc_version)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'running', 0, 0, 0, '2026.1')$$,
    '23514', NULL, '0-minute workout rejected'
);
SELECT lives_ok(
    $$INSERT INTO activity.workout (id, performed_at, user_id, local_date, workout_type, duration_min, sweat_ml, kcal, calc_version)
                  VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'running', 600, 1000, 784, '2026.1')$$,
    '600-minute workout accepted'
);
SELECT throws_ok(
    $$INSERT INTO activity.workout (id, performed_at, user_id, local_date, workout_type, duration_min, sweat_ml, kcal, calc_version)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'running', 601, 0, 0, '2026.1')$$,
    '23514', NULL, '601-minute workout rejected'
);

-- ---------------------------------------------------------------- sleep
SELECT lives_ok(
    $$INSERT INTO sleep.entry (id, user_id, sleep_start, wake_time, wake_local_date, counted_min)
                  VALUES ('0192f000-0000-7000-8000-0000000000b1', '0192f000-0000-7000-8000-0000000000a1',
                          '2026-10-20 23:00+05:30', '2026-10-21 07:00+05:30', '2026-10-21', 450)$$,
    'sleep entry 23:00-07:00 accepted'
);
SELECT throws_ok(
    $$INSERT INTO sleep.entry (id, user_id, sleep_start, wake_time, wake_local_date, counted_min)
                   VALUES (uuidv7(), '0192f000-0000-7000-8000-0000000000a1',
                           '2026-10-21 06:00+05:30', '2026-10-21 08:00+05:30', '2026-10-21', 90)$$,
    '23P01', NULL, 'overlapping sleep entry rejected (exclusion constraint)'
);
SELECT throws_ok(
    $$INSERT INTO sleep.entry (id, user_id, sleep_start, wake_time, wake_local_date, counted_min)
                   VALUES (uuidv7(), '0192f000-0000-7000-8000-0000000000a1',
                           '2026-10-22 00:00+05:30', '2026-10-22 16:01+05:30', '2026-10-22', 900)$$,
    '23514', NULL, 'entry longer than 16 h rejected'
);
SELECT throws_ok(
    $$INSERT INTO sleep.night_waking (entry_id, user_id, woke_at, back_asleep_at)
                   VALUES ('0192f000-0000-7000-8000-0000000000b1', '0192f000-0000-7000-8000-0000000000a1',
                           '2026-10-21 02:20+05:30', '2026-10-21 02:00+05:30')$$,
    '23514', NULL, 'waking that ends before it starts rejected'
);

-- ---------------------------------------------------------------- meals
INSERT INTO nutrition.food_item (id, name, category_code, basis, is_cooked, source_ref, calories_kcal)
VALUES ('0192f000-0000-7000-8000-0000000000f1', 'Test Food', 'roti', 'g', TRUE, 'test fixture', 100);
INSERT INTO nutrition.meal (id, logged_at, user_id, local_date, meal_type, source)
VALUES ('0192f000-0000-7000-8000-0000000000c1', now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'lunch', 'search');
SELECT throws_ok(
    $$INSERT INTO nutrition.meal_item (meal_id, meal_logged_at, user_id, food_id, quantity, unit_code, unit_size, consumed_amount, consumed_basis)
                   SELECT id, logged_at, user_id, '0192f000-0000-7000-8000-0000000000f1', 0.2, 'piece', 'medium', 8, 'g'
                   FROM nutrition.meal WHERE id = '0192f000-0000-7000-8000-0000000000c1'$$,
    '23514', NULL, 'quantity 0.2 rejected (min 0.25)'
);
SELECT throws_ok(
    $$INSERT INTO nutrition.food_item (name, category_code, basis, is_cooked, source_ref, calories_kcal)
                   VALUES ('Impossible', 'roti', 'g', true, 'test', 901)$$,
    '23514', NULL, '901 kcal per 100 g rejected'
);
SELECT throws_ok(
    $$INSERT INTO nutrition.food_item (name, category_code, basis, is_cooked, source_ref, protein_g, carbohydrates_g, fat_g)
                   VALUES ('Impossible macros', 'roti', 'g', true, 'test', 50, 40, 20)$$,
    '23514', NULL, 'macros above 100 g per 100 g rejected'
);
SELECT throws_ok(
    $$INSERT INTO nutrition.meal (id, logged_at, user_id, local_date, meal_type, source)
                   VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-0000000000a1', current_date, 'brunch', 'search')$$,
    '23514', NULL, 'unknown meal type rejected'
);

-- ---------------------------------------------------------------- auth
SELECT throws_ok(
    $$INSERT INTO auth.user_account (email)
                   VALUES ('u01@example.test')$$,
    '23505', NULL, 'duplicate email rejected'
);
SELECT throws_ok(
    $$INSERT INTO auth.otp_challenge (email, purpose, code, expires_at, attempts)
                   VALUES ('u01@example.test', 'email_verification', '123456', now() + interval '5 minutes', 4)$$,
    '23514', NULL, 'more than 3 OTP attempts rejected'
);
SELECT throws_ok(
    $$INSERT INTO auth.refresh_token (user_id, family_id, token_hash, expires_at, revoked_at)
                   VALUES ('0192f000-0000-7000-8000-0000000000a1', uuidv7(), decode(repeat('02', 32), 'hex'),
                           now() + interval '60 days', now())$$,
    '23514', NULL, 'revoked token must carry a revoked_reason'
);

-- ---------------------------------------------------------------- billing
SELECT throws_ok(
    $$INSERT INTO billing.subscription (user_id, platform, product_id, status, auto_renew,
                       current_period_start, current_period_end, environment, last_verified_at)
                   VALUES ('0192f000-0000-7000-8000-0000000000a1', 'google_play', 'star_monthly', 'active', true,
                           now(), now() + interval '1 month', 'sandbox', now())$$,
    '23514', NULL, 'Play subscription without purchase token rejected'
);

SELECT * FROM finish();
ROLLBACK;
