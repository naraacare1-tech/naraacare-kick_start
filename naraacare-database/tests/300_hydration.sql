-- Hydration: drinks and tiers, swipe-down rule, edit window, temperature, custom drinks, day inputs,
-- daily summary and IDOR (Session 09; doc 06 section 3, OQ-04, OQ-05, OQ-53).
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

-- u1: STANDARD. u2: STAR through a promo grant. u3: not onboarded. All in Asia/Kolkata.
INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000003c1', 'uc1@example.test', 'active'),
('0192f000-0000-7000-8000-0000000003c2', 'uc2@example.test', 'active'),
('0192f000-0000-7000-8000-0000000003c3', 'uc3@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at)
VALUES ('0192f000-0000-7000-8000-0000000003c1', 6, now()), ('0192f000-0000-7000-8000-0000000003c2', 6, now());
INSERT INTO app.user_profile (user_id, onboarding_step) VALUES ('0192f000-0000-7000-8000-0000000003c3', 2);
INSERT INTO app.health_target_snapshot (
    user_id, effective_date, calc_version, inputs, bmi, bmi_category, bmr_kcal, tdee_kcal, goal_delta_kcal,
    calculated_target_kcal, base_target_kcal, safety_override, carbs_g, fat_g, protein_g,
    lean_body_weight_kg, water_movement_ml, base_water_need_ml
)
SELECT
    u,
    current_date - 30,
    '2026.1',
    '{"sex": "female", "age_years": 32, "height_cm": 162, "weight_kg": 65, "body_type": "endomorph", "activity_level": "sedentary"}',
    24.8,
    'normal',
    1300,
    975,
    0,
    975,
    1200,
    TRUE,
    165,
    33,
    60,
    46.05,
    3592.1,
    3053
FROM unnest(ARRAY['0192f000-0000-7000-8000-0000000003c1'::uuid, '0192f000-0000-7000-8000-0000000003c2'::uuid]) AS u;
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-0000000003c2', 'star', 'promo', now() - interval '1 day', now() + interval '30 days');

CREATE FUNCTION pg_temp.drink(
    p_user uuid, p_id uuid, p_at timestamptz, p_code text, p_ml integer, p_source text DEFAULT 'manual',
    p_custom uuid DEFAULT NULL
) RETURNS text LANGUAGE plpgsql AS $$
DECLARE s text; d date;
BEGIN
    CALL hydration.pr_log_intake(p_user, p_id, p_at, p_code, p_custom, p_ml, p_source, s, d);
    RETURN s;
END
$$;
CREATE FUNCTION pg_temp.id(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(8192 + n), 12, '0'))::uuid
$$;
-- Fixed hours on YESTERDAY's local date (IST), so the test never straddles midnight.
CREATE FUNCTION pg_temp.at(p_hours numeric) RETURNS timestamptz LANGUAGE sql AS $$
    SELECT ((common.fn_local_date('Asia/Kolkata') - 1)::timestamp + p_hours * interval '1 hour') AT TIME ZONE 'Asia/Kolkata'
$$;
CREATE FUNCTION pg_temp.yday() RETURNS date LANGUAGE sql AS $$ SELECT common.fn_local_date('Asia/Kolkata') - 1 $$;
CREATE FUNCTION pg_temp.version(p_id uuid) RETURNS integer LANGUAGE sql AS $$
    SELECT version FROM hydration.intake WHERE id = p_id
$$;

-- ===== Drinks list (OQ-05) =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003c1', TRUE);
SELECT is(
    (SELECT string_agg(drink_code || ':' || locked, ',' ORDER BY display_order) FROM hydration.fn_drinks_for_user('0192f000-0000-7000-8000-0000000003c1')),
    'water:false,tea:false,milk:false,coconut_water:false,coffee:true,juice:true,beer:true',
    'STANDARD: 4 standard drinks unlocked, coffee/juice/beer locked'
);

-- ===== Logging =====
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(1), pg_temp.at(7.5), 'water', 100), 'created', 'water is saved');
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(1), pg_temp.at(7.5), 'water', 100), 'duplicate', 'a replay changes nothing');
SELECT is(
    (
        SELECT row(volume_ml, effective_intake_ml)::text FROM hydration.daily_summary
        WHERE user_id = '0192f000-0000-7000-8000-0000000003c1' AND local_date = pg_temp.yday()
    ),
    '(100,100.0)', 'the summary counts the drink once'
);
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(2), pg_temp.at(9.5), 'milk', 200), 'created', 'milk is saved');
SELECT is(
    (
        SELECT row(hydration_factor, effective_ml)::text FROM hydration.intake
        WHERE id = pg_temp.id(2)
    ),
    '(0.880,176.0)', 'the factor is snapshotted and effective mL = volume x factor'
);
SELECT ok(
    (
        SELECT has_hydration FROM app.user_activity_day
        WHERE user_id = '0192f000-0000-7000-8000-0000000003c1' AND local_date = pg_temp.yday()
    ),
    'the day is marked active for streaks'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), pg_temp.at(10), 'coffee', 200)$$,
    'P0001', NULL, 'STANDARD: coffee is refused (UPGRADE_REQUIRED)'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), pg_temp.at(10), 'water', 3001)$$,
    '22023', NULL, 'more than 3000 mL is refused'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), pg_temp.at(10), 'water', 0)$$,
    '22023', NULL, '0 mL is refused'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), pg_temp.at(10), 'tea', -100, 'swipe')$$,
    '22023', NULL, '-100 is only a water swipe (not tea)'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), pg_temp.at(10), 'water', -100, 'manual')$$,
    '22023', NULL, '-100 is only a water swipe (not manual)'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), now() + interval '10 minutes', 'water', 100)$$,
    '22023', NULL, 'more than 5 minutes in the future is refused'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), now() - interval '9 days', 'water', 100)$$,
    'P0001', NULL, 'older than 7 days is refused (EDIT_WINDOW_CLOSED)'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(3), pg_temp.at(10), 'smoothie', 100)$$,
    '22023', NULL, 'an unknown drink code is refused'
);

-- ===== Swipe-down rule: the day's water never goes below 0 =====
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(4), pg_temp.at(10), 'water', -100, 'swipe'), 'created', 'swipe down removes 100 mL of water');
SELECT is(
    (
        SELECT volume_ml FROM hydration.daily_summary
        WHERE user_id = '0192f000-0000-7000-8000-0000000003c1' AND local_date = pg_temp.yday()
    ),
    200, 'the day: 100 water - 100 swipe + 200 milk'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(5), pg_temp.at(10.5), 'water', -100, 'swipe')$$,
    'P0001', 'the day''s water cannot go below 0', 'a second swipe down would make the day''s water negative (milk does not count)'
);
SELECT is((
    SELECT count(*)::integer FROM hydration.intake
    WHERE id = pg_temp.id(5)
), 0, 'the refused swipe left nothing behind');

-- ===== Edit window: last 2 within 7 days, If-Match version =====
SELECT is(
    (SELECT string_agg(intake_id::text || ':' || editable, ',' ORDER BY logged_at) FROM hydration.fn_intakes('0192f000-0000-7000-8000-0000000003c1', pg_temp.yday())),
    format('%s:false,%s:true,%s:true', pg_temp.id(1), pg_temp.id(2), pg_temp.id(4)),
    'only the last 2 drinks are editable'
);
SELECT throws_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1, 250, NULL, NULL, NULL)$$, pg_temp.id(1)),
    'P0001', 'only the last 2 drinks within 7 days can change', 'the 3rd-last drink cannot be edited (EDIT_WINDOW_CLOSED)'
);
SELECT throws_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 9, 250, NULL, NULL, NULL)$$, pg_temp.id(2)),
    'P0001', 'drink was changed elsewhere', 'a stale version is refused (VERSION_CONFLICT)'
);
SELECT lives_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1, 250, 'tea', NULL, NULL)$$, pg_temp.id(2)),
    'the milk becomes 250 mL of tea'
);
SELECT is(
    (
        SELECT row(drink_code, volume_ml, hydration_factor, effective_ml, version)::text FROM hydration.intake
        WHERE id = pg_temp.id(2)
    ),
    '(tea,250,0.997,249.3,2)', 'edit: new drink, factor re-snapshotted, version + 1'
);
SELECT throws_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 2, NULL, 'juice', NULL, NULL)$$, pg_temp.id(2)),
    'P0001', 'this drink needs STAR', 'STANDARD cannot change a drink to juice'
);
SELECT throws_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 2, -100, NULL, NULL, NULL)$$, pg_temp.id(2)),
    '22023', NULL, 'a normal drink cannot become -100'
);
SELECT throws_ok(
    format($$CALL hydration.pr_delete_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1)$$, pg_temp.id(1)),
    'P0001', NULL, 'the 3rd-last drink cannot be deleted'
);
SELECT lives_ok(
    format($$CALL hydration.pr_delete_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1)$$, pg_temp.id(4)),
    'the swipe-down entry is deleted'
);
SELECT is(
    (
        SELECT row(volume_ml, effective_intake_ml)::text FROM hydration.daily_summary
        WHERE user_id = '0192f000-0000-7000-8000-0000000003c1' AND local_date = pg_temp.yday()
    ),
    '(350,349.3)', 'the summary is rebuilt after the delete'
);
-- Now id(1) (water 100) is editable again; a new swipe then deleting the water would go negative.
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(6), pg_temp.at(11), 'water', -100, 'swipe'), 'created', 'swipe down again');
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(7), pg_temp.at(12), 'water', 300), 'created', 'more water');
SELECT lives_ok(
    format($$CALL hydration.pr_delete_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1)$$, pg_temp.id(7)),
    'delete the 300 mL (water stays at 0)'
);
SELECT throws_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1, NULL, 'tea', NULL, NULL)$$, pg_temp.id(6)),
    '22023', NULL, 'a swipe-down cannot become tea'
);

-- ===== Temperature (STAR, OQ-04) =====
SELECT throws_ok(
    $$CALL hydration.pr_set_temperature('0192f000-0000-7000-8000-0000000003c1', 35, NULL)$$,
    'P0001', 'temperature needs STAR', 'STANDARD cannot set a temperature (doc 06 section 3.11)'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003c2', TRUE);
SELECT throws_ok($$CALL hydration.pr_set_temperature('0192f000-0000-7000-8000-0000000003c2', 14.9, NULL)$$, '22023', NULL, 'below 15 C is refused');
SELECT throws_ok($$CALL hydration.pr_set_temperature('0192f000-0000-7000-8000-0000000003c2', 40.1, NULL)$$, '22023', NULL, 'above 40 C is refused');
SELECT throws_ok($$CALL hydration.pr_set_temperature('0192f000-0000-7000-8000-0000000003c2', 30.25, NULL)$$, '22023', NULL, 'more than one decimal is refused');
SELECT lives_ok($$CALL hydration.pr_set_temperature('0192f000-0000-7000-8000-0000000003c2', 30.5, NULL)$$, 'STAR sets 30.5 C');
SELECT is(
    (SELECT jsonb_array_length(hydration.fn_day_inputs('0192f000-0000-7000-8000-0000000003c2', NULL) -> 'temperatures')),
    1, 'today''s inputs include the temperature'
);

-- ===== STAR drinks and custom drinks =====
SELECT is(pg_temp.drink('0192f000-0000-7000-8000-0000000003c2', pg_temp.id(20), pg_temp.at(8), 'coffee', 200), 'created', 'STAR logs coffee');
SELECT is(
    (
        SELECT count(*)::integer FROM hydration.fn_drinks_for_user('0192f000-0000-7000-8000-0000000003c2')
        WHERE locked
    ),
    0, 'STAR: nothing locked'
);
CREATE TEMP TABLE cd (id uuid);
DO $$
DECLARE v uuid;
BEGIN
    CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'Banana Shake', 0.82, 'ai', v);
    INSERT INTO cd VALUES (v);
END
$$;
SELECT is(
    (
        SELECT string_agg(label || ':' || hydration_factor || ':' || locked, ',') FROM hydration.fn_drinks_for_user('0192f000-0000-7000-8000-0000000003c2')
        WHERE kind = 'custom'
    ),
    'Banana Shake:0.820:false', 'the custom drink is listed for its owner'
);
SELECT throws_ok(
    $$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'banana shake', 0.8, 'user', NULL)$$,
    'P0001', 'a custom drink with this name exists', 'names are unique per user ignoring case (ALREADY_EXISTS)'
);
SELECT throws_ok($$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'Lassi', 1.2, 'user', NULL)$$, '22023', NULL, 'a factor above 1 is refused');
SELECT throws_ok($$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'Lassi', 0.8125, 'user', NULL)$$, '22023', NULL, 'more than 3 decimals is refused');
SELECT throws_ok($$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'Lassi', 0.8, 'model', NULL)$$, '22023', NULL, 'an unknown estimate source is refused');
SELECT throws_ok($$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', '   ', 0.8, 'user', NULL)$$, '22023', NULL, 'a blank name is refused');
SELECT
    throws_ok(
        format($$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', %L, 0.8, 'user', NULL)$$, payload),
        '22023', NULL, format('payload #%s rejected as a custom drink name', id)
    )
FROM test_payloads
WHERE char_length(btrim(payload)) BETWEEN 1 AND 60
ORDER BY id;
SELECT is(
    pg_temp.drink('0192f000-0000-7000-8000-0000000003c2', pg_temp.id(21), pg_temp.at(9), NULL, 300, 'manual', (SELECT id FROM cd)),
    'created', 'STAR logs the custom drink'
);
SELECT is((
    SELECT effective_ml FROM hydration.intake
    WHERE id = pg_temp.id(21)
), 246.0, 'custom drink: 300 x 0.82');
DO $$
DECLARE v uuid;
BEGIN
    FOR n IN 1..99 LOOP
        CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'Drink ' || n, 0.9, 'user', v);
    END LOOP;
END
$$;
SELECT throws_ok(
    $$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c2', 'One too many', 0.9, 'user', NULL)$$,
    'P0001', 'at most 100 custom drinks', 'at most 100 custom drinks (CUSTOM_DRINK_LIMIT)'
);

-- STANDARD (or a downgraded user) cannot use or save custom drinks; another user's drink is not found.
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003c1', TRUE);
SELECT throws_ok(
    $$CALL hydration.pr_save_custom_drink('0192f000-0000-7000-8000-0000000003c1', 'Lassi', 0.8, 'user', NULL)$$,
    'P0001', 'custom drinks need STAR', 'STANDARD cannot save custom drinks'
);
SELECT throws_ok(
    format($$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c1', pg_temp.id(8), pg_temp.at(13), NULL, 100, 'manual', %L)$$, (SELECT id FROM cd)),
    'P0001', 'custom drinks need STAR', 'STANDARD cannot log a custom drink'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003c2', TRUE);
UPDATE billing.entitlement_grant SET ends_at = now() + interval '30 days'
WHERE user_id = '0192f000-0000-7000-8000-0000000003c2';

-- ===== IDOR =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003c1', TRUE);
SELECT throws_ok(
    format($$CALL hydration.pr_update_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1, 100, NULL, NULL, NULL)$$, pg_temp.id(20)),
    '42501', NULL, 'another user''s drink cannot be edited (404)'
);
SELECT throws_ok(
    format($$CALL hydration.pr_delete_intake('0192f000-0000-7000-8000-0000000003c1', %L, 1)$$, pg_temp.id(20)),
    '42501', NULL, 'another user''s drink cannot be deleted (404)'
);
SELECT is(
    (SELECT count(*)::integer FROM hydration.fn_intakes('0192f000-0000-7000-8000-0000000003c1', NULL, pg_temp.id(20))),
    0, 'another user''s drink is not readable'
);
SELECT throws_ok(
    $$SELECT hydration.fn_day_inputs('0192f000-0000-7000-8000-0000000003c2', NULL)$$,
    '42501', NULL, 'another user''s day inputs are not readable'
);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c2', pg_temp.id(9), pg_temp.at(13), 'water', 100)$$,
    '42501', NULL, 'nobody can log for another user'
);

-- ===== Day inputs and daily summary =====
SELECT is(
    (
        SELECT
            row(
                j ->> 'date', j ->> 'timezone', j ->> 'wake_local', j ->> 'sleep_start_local', j ->> 'tier',
                j ->> 'advanced', j -> 'inputs' ->> 'weight_kg', jsonb_array_length(j -> 'intakes'),
                jsonb_array_length(j -> 'temperatures')
            )::text
        FROM hydration.fn_day_inputs('0192f000-0000-7000-8000-0000000003c1', pg_temp.yday()) AS j
    ),
    format('(%s,Asia/Kolkata,07:00,23:00,standard,false,65,3,0)', pg_temp.yday()),
    'day inputs: profile times, tier, snapshot and the non-deleted drinks'
);
SELECT is(
    (SELECT j -> 'intakes' -> 0 ->> 'effective_ml' FROM hydration.fn_day_inputs('0192f000-0000-7000-8000-0000000003c1', pg_temp.yday()) AS j),
    '100.0', 'intakes in time order with effective mL'
);
CREATE TEMP TABLE first_flags (n integer, first boolean);
DO $$
DECLARE f boolean;
BEGIN
    CALL hydration.pr_upsert_daily_summary('0192f000-0000-7000-8000-0000000003c1', common.fn_local_date('Asia/Kolkata') - 1, 3053, 204, FALSE, '2026.1', f);
    INSERT INTO first_flags VALUES (1, f);
    CALL hydration.pr_upsert_daily_summary('0192f000-0000-7000-8000-0000000003c1', common.fn_local_date('Asia/Kolkata') - 1, 3053, 204, TRUE, '2026.1', f);
    INSERT INTO first_flags VALUES (2, f);
    CALL hydration.pr_upsert_daily_summary('0192f000-0000-7000-8000-0000000003c1', common.fn_local_date('Asia/Kolkata') - 1, 3100, 204, FALSE, '2026.1', f);
    INSERT INTO first_flags VALUES (3, f);
    CALL hydration.pr_upsert_daily_summary('0192f000-0000-7000-8000-0000000003c1', common.fn_local_date('Asia/Kolkata') - 9, 3053, 0, TRUE, '2026.1', f);
    INSERT INTO first_flags VALUES (4, f);
END
$$;
SELECT is((SELECT string_agg(first::text, ',' ORDER BY n) FROM first_flags), 'false,true,false,false', 'goal completion is reported once; days older than 7 days are ignored');
SELECT is(
    (
        SELECT row(daily_need_ml, food_water_ml, goal_completed_at IS NOT NULL)::text FROM hydration.daily_summary
        WHERE user_id = '0192f000-0000-7000-8000-0000000003c1' AND local_date = pg_temp.yday()
    ),
    '(3100,204.0,t)', 'need and food water stored; completion is never cleared'
);
SELECT throws_ok(
    $$CALL hydration.pr_upsert_daily_summary('0192f000-0000-7000-8000-0000000003c1', common.fn_local_date('Asia/Kolkata'), 9000, 0, FALSE, '2026.1', NULL)$$,
    '23514', NULL, 'a need outside 1500..6000 is refused (CHECK)'
);

-- ===== Not onboarded =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003c3', TRUE);
SELECT throws_ok(
    $$SELECT pg_temp.drink('0192f000-0000-7000-8000-0000000003c3', pg_temp.id(30), pg_temp.at(8), 'water', 100)$$,
    'P0001', 'complete onboarding first', 'logging needs a completed onboarding'
);
SELECT throws_ok(
    $$SELECT hydration.fn_day_inputs('0192f000-0000-7000-8000-0000000003c3', NULL)$$,
    'P0001', 'complete onboarding first', 'status needs a completed onboarding'
);

-- ===== Grants =====
SELECT ok(has_function_privilege('app_rw', 'hydration.fn_day_inputs(uuid, date)', 'EXECUTE'), 'app_rw may read day inputs');
SELECT ok(NOT has_function_privilege('app_rw', 'hydration.fn_editable_intake_ids(uuid)', 'EXECUTE'), 'internal helpers are not granted to app_rw');
SELECT ok(NOT has_function_privilege('app_rw', 'hydration.pr_refresh_daily_summary(uuid, date)', 'EXECUTE'), 'the summary rebuild is internal');

SELECT * FROM finish();
ROLLBACK;
