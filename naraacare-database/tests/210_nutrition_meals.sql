-- Meal logging, limits, edit window, backdating, hydration credits, summaries, saved meals and IDOR
-- (Session 08; doc 06 sections 2.8-2.11, OQ-09, OQ-18, OQ-53).
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

-- u1: STANDARD (limit 4). u2: STAR through a promo grant (limit 8). Both onboarded, timezone Asia/Kolkata.
INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000002b1', 'ub1@example.test', 'active'),
('0192f000-0000-7000-8000-0000000002b2', 'ub2@example.test', 'active'),
('0192f000-0000-7000-8000-0000000002b3', 'ub3@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at)
VALUES ('0192f000-0000-7000-8000-0000000002b1', 6, now()), ('0192f000-0000-7000-8000-0000000002b2', 6, now());
INSERT INTO app.health_target_snapshot (
    user_id, effective_date, calc_version, inputs, bmi, bmi_category, bmr_kcal, tdee_kcal, goal_delta_kcal,
    calculated_target_kcal, base_target_kcal, safety_override, carbs_g, fat_g, protein_g,
    lean_body_weight_kg, water_movement_ml, base_water_need_ml
)
SELECT
    u,
    current_date - 30,
    '2026.1',
    '{}',
    21.6,
    'normal',
    1680,
    1714,
    500,
    2214,
    2214,
    FALSE,
    304,
    62,
    111,
    55,
    3000,
    2500
FROM unnest(ARRAY['0192f000-0000-7000-8000-0000000002b1'::uuid, '0192f000-0000-7000-8000-0000000002b2'::uuid]) AS u;
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-0000000002b2', 'star', 'promo', now() - interval '1 day', now() + interval '30 days');

CREATE FUNCTION pg_temp.item(p_food text, p_qty numeric, p_unit text) RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_array(jsonb_build_object('food_id', p_food, 'quantity', p_qty, 'unit_code', p_unit))
$$;
CREATE FUNCTION pg_temp.log(p_user uuid, p_meal uuid, p_at timestamptz, p_items jsonb, p_source text DEFAULT 'search')
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s text; d date;
BEGIN
    CALL nutrition.pr_log_meal(p_user, p_meal, p_at, 'lunch', p_source, p_items, s, d);
    RETURN s;
END
$$;
CREATE FUNCTION pg_temp.meal(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(4096 + n), 12, '0'))::uuid
$$;
-- Fixed hours on YESTERDAY's local date (IST), so the test never straddles midnight.
CREATE FUNCTION pg_temp.at(p_hours numeric) RETURNS timestamptz LANGUAGE sql AS $$
    SELECT ((common.fn_local_date('Asia/Kolkata') - 1)::timestamp + p_hours * interval '1 hour') AT TIME ZONE 'Asia/Kolkata'
$$;
CREATE FUNCTION pg_temp.yday() RETURNS date LANGUAGE sql AS $$ SELECT common.fn_local_date('Asia/Kolkata') - 1 $$;

SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b1', TRUE);
SELECT is(
    (SELECT row(meal_count, (totals ->> 'calories')::numeric, base_target_kcal, effective_allowance_kcal, meal_limit, last_updated)::text FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())),
    '(0,0,2214,2214,4,)', 'a day without meals: zeros, today''s target and the STANDARD limit'
);

-- ===== Logging =====
SELECT is(
    pg_temp.log(
        '0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(1), pg_temp.at(8),
        pg_temp.item('0192f000-0000-7000-8000-000000000001', 1, 'piece')
    ),
    'created', 'a meal is saved'
);
SELECT is(
    (SELECT row(meal_count, round((totals ->> 'calories')::numeric), round((totals ->> 'vitamin_c')::numeric, 1))::text FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())),
    '(1,78,6.9)', 'the daily summary includes the apple (78 kcal, 6.9 mg vitamin C)'
);
SELECT is(
    pg_temp.log(
        '0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(1), pg_temp.at(8),
        pg_temp.item('0192f000-0000-7000-8000-000000000001', 1, 'piece')
    ),
    'duplicate', 'replaying the same client id changes nothing (offline sync)'
);
SELECT is((SELECT meal_count FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())), 1, 'still one meal after the replay');
SELECT ok(
    (
        SELECT has_nutrition FROM app.user_activity_day
        WHERE user_id = '0192f000-0000-7000-8000-0000000002b1' AND local_date = pg_temp.yday()
    ),
    'the day is marked active for streaks'
);

SELECT lives_ok(
    $$
    SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(2), pg_temp.at(9), pg_temp.item('0192f000-0000-7000-8000-000000000003', 2, 'piece'));
    SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(3), pg_temp.at(10), pg_temp.item('0192f000-0000-7000-8000-000000000004', 1, 'katori'));
    SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(4), pg_temp.at(11), pg_temp.item('0192f000-0000-7000-8000-000000000007', 1, 'katori'));
    $$,
    'meals 2-4 are saved'
);
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(5), pg_temp.at(12), pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'))$$,
    'P0001', NULL, 'STANDARD: the 5th meal of the day is refused (DAILY_LIMIT_REACHED)'
);
SELECT is(
    (SELECT round((totals ->> 'calories')::numeric, 3) FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())),
    (
        SELECT round(sum(calories_kcal), 3) FROM nutrition.meal_item
        WHERE user_id = '0192f000-0000-7000-8000-0000000002b1' AND deleted_at IS NULL
    ),
    'summary totals equal the sum of the item snapshots'
);
SELECT is(
    (
        SELECT array_agg(hydration_credit ORDER BY logged_at) FROM nutrition.meal
        WHERE user_id = '0192f000-0000-7000-8000-0000000002b1'
    ),
    ARRAY[TRUE, TRUE, TRUE, FALSE], 'only the first 3 meals of the day carry the hydration food credit'
);

-- ===== Edit window: last 2 meals, If-Match =====
SELECT is(
    (SELECT array_agg(editable ORDER BY logged_at) FROM nutrition.fn_recent_meals('0192f000-0000-7000-8000-0000000002b1')),
    ARRAY[FALSE, FALSE, TRUE, TRUE], 'only the last 2 meals are editable'
);
SELECT throws_ok(
    format($$CALL nutrition.pr_update_meal('0192f000-0000-7000-8000-0000000002b1', %L, 1, 'dinner', NULL, NULL)$$, pg_temp.meal(1)),
    'P0001', NULL, 'an older meal cannot be edited (EDIT_WINDOW_CLOSED)'
);
SELECT throws_ok(
    format($$CALL nutrition.pr_delete_meal('0192f000-0000-7000-8000-0000000002b1', %L, 1)$$, pg_temp.meal(2)),
    'P0001', NULL, 'an older meal cannot be deleted'
);
SELECT throws_ok(
    format($$CALL nutrition.pr_update_meal('0192f000-0000-7000-8000-0000000002b1', %L, 7, 'dinner', NULL, NULL)$$, pg_temp.meal(4)),
    'P0001', NULL, 'a stale version is refused (VERSION_CONFLICT)'
);
SELECT lives_ok(
    format(
        $$CALL nutrition.pr_update_meal('0192f000-0000-7000-8000-0000000002b1', %L, 1, 'dinner', %L, NULL)$$,
        pg_temp.meal(4), pg_temp.item('0192f000-0000-7000-8000-000000000007', 2, 'katori')
    ),
    'the latest meal can be edited with the current version'
);
SELECT is(
    (SELECT row(meal_type, version, round((totals ->> 'calories')::numeric))::text FROM nutrition.fn_meal_breakdown('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(4))),
    '(dinner,2,390)', 'edited meal: new type, version 2, new snapshot (2 katori rice = 390 kcal)'
);
SELECT is(
    (SELECT meal_count FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())), 4,
    'editing does not count toward the limit'
);
SELECT lives_ok(
    format($$CALL nutrition.pr_delete_meal('0192f000-0000-7000-8000-0000000002b1', %L, 1)$$, pg_temp.meal(3)),
    'the second-to-last meal can be deleted'
);
SELECT is(
    (
        SELECT array_agg(hydration_credit ORDER BY logged_at) FROM nutrition.meal
        WHERE user_id = '0192f000-0000-7000-8000-0000000002b1' AND deleted_at IS NULL
    ),
    ARRAY[TRUE, TRUE, TRUE], 'after a delete the credits move to the first 3 remaining meals'
);
SELECT is(
    (SELECT round((totals ->> 'calories')::numeric, 3) FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())),
    (
        SELECT round(sum(i.calories_kcal), 3) FROM nutrition.meal_item AS i
        WHERE i.user_id = '0192f000-0000-7000-8000-0000000002b1' AND i.deleted_at IS NULL
    ),
    'totals are rebuilt after edit and delete'
);
SELECT is(
    pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(5), pg_temp.at(12), pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece')),
    'created', 'a deleted meal frees a slot (non-deleted meals count, OQ-09)'
);

-- ===== Backdating and time checks (OQ-53) =====
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(6), now() - interval '9 days', pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'))$$,
    'P0001', NULL, 'entries older than 7 days are refused (EDIT_WINDOW_CLOSED)'
);
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(6), now() + interval '1 hour', pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'))$$,
    '22023', NULL, 'future entries are refused'
);
SELECT is(
    pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(6), now() - interval '3 days', pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece')),
    'created', 'an offline entry from 3 days ago is accepted'
);
SELECT is(
    (SELECT meal_count FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b1', common.fn_local_date('Asia/Kolkata', now() - interval '3 days'))),
    1, '... and lands on its own local day'
);

-- ===== Tier rules =====
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(7), now() - interval '2 days', pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'), 'voice')$$,
    'P0001', NULL, 'STANDARD cannot log with voice (UPGRADE_REQUIRED)'
);
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b1', pg_temp.meal(7), now() - interval '2 days', pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'), 'barcode')$$,
    'P0001', NULL, 'STANDARD cannot log from a barcode'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b2', TRUE);
SELECT is(
    (SELECT
        array_agg(pg_temp.log(
            '0192f000-0000-7000-8000-0000000002b2', pg_temp.meal(100 + n), pg_temp.at(13 + n / 60.0),
            pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'), CASE WHEN n = 1 THEN 'voice' ELSE 'search' END
        ))
    FROM generate_series(1, 8) AS n),
    array_fill('created'::text, ARRAY[8]), 'STAR: 8 meals a day, voice allowed'
);
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b2', pg_temp.meal(109), pg_temp.at(15), pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'))$$,
    'P0001', NULL, 'STAR: the 9th meal is refused'
);
SELECT is((SELECT meal_limit FROM nutrition.fn_daily_summary('0192f000-0000-7000-8000-0000000002b2')), 8, 'STAR limit is 8');

-- ===== IDOR: u2 cannot see or touch u1's meals =====
SELECT throws_ok(
    $$SELECT * FROM nutrition.fn_meals_by_date('0192f000-0000-7000-8000-0000000002b1', current_date)$$,
    '42501', NULL, 'reading another user''s meals is refused (-> 404)'
);
SELECT throws_ok(
    format($$CALL nutrition.pr_update_meal('0192f000-0000-7000-8000-0000000002b2', %L, 2, 'snack', NULL, NULL)$$, pg_temp.meal(4)),
    '42501', NULL, 'editing another user''s meal through one''s own id finds nothing (-> 404)'
);
SELECT throws_ok(
    format($$CALL nutrition.pr_delete_meal('0192f000-0000-7000-8000-0000000002b2', %L, 2)$$, pg_temp.meal(4)),
    '42501', NULL, 'deleting another user''s meal finds nothing'
);
SELECT is(
    (SELECT count(*)::integer FROM nutrition.fn_meal_breakdown('0192f000-0000-7000-8000-0000000002b2', pg_temp.meal(4))),
    0, 'no breakdown for another user''s meal'
);
SELECT is(
    pg_temp.log('0192f000-0000-7000-8000-0000000002b2', pg_temp.meal(1), now() - interval '2 days', pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece')),
    'created', 'a client id used by another user does not leak their meal (separate rows)'
);
SELECT throws_ok(
    $$CALL nutrition.pr_log_meal('0192f000-0000-7000-8000-0000000002b3', gen_random_uuid(), now(), 'lunch', 'search', '[]', NULL, NULL)$$,
    '42501', NULL, 'logging for another user id is refused'
);

-- ===== Reads =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b1', TRUE);
SELECT is(
    (
        SELECT jsonb_array_length(items) FROM nutrition.fn_meals_by_date('0192f000-0000-7000-8000-0000000002b1', pg_temp.yday())
        WHERE meal_id = pg_temp.meal(4)
    ),
    1, 'meals come with their items'
);
SELECT is(
    (SELECT array_agg(name ORDER BY last_logged_at DESC) FROM nutrition.fn_recent_foods('0192f000-0000-7000-8000-0000000002b1')),
    ARRAY['Banana', 'Rice (Cooked)', 'Roti (Whole Wheat)', 'Apple'], 'recent food chips: distinct foods, newest first, deleted meals excluded'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b3', TRUE);
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-0000000002b3', gen_random_uuid(), now(), pg_temp.item('0192f000-0000-7000-8000-000000000002', 1, 'piece'))$$,
    'P0001', NULL, 'meals need a completed onboarding (ONBOARDING_INCOMPLETE)'
);

-- ===== Saved meals =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b1', TRUE);
CREATE TEMP TABLE sm (id uuid);
DO $$
DECLARE v uuid;
BEGIN
    CALL nutrition.pr_save_meal_template('0192f000-0000-7000-8000-0000000002b1', '  Dal Chawal  ',
        '[{"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "katori"}, {"food_id": "0192f000-0000-7000-8000-000000000007", "quantity": 1, "unit_code": "katori"}]', v);
    INSERT INTO sm VALUES (v);
END
$$;
SELECT is(
    (SELECT row(name, jsonb_array_length(items), items -> 0 ->> 'unit_size')::text FROM nutrition.fn_saved_meals('0192f000-0000-7000-8000-0000000002b1')),
    '("Dal Chawal",2,medium)', 'saved meal: trimmed name, items with the resolved size'
);
SELECT throws_ok(
    $$CALL nutrition.pr_save_meal_template('0192f000-0000-7000-8000-0000000002b1', 'Bad', '[{"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 0.1, "unit_code": "katori"}]', NULL)$$,
    '22023', NULL, 'saved meal items are validated like meal items'
);
SELECT throws_ok(
    $$CALL nutrition.pr_save_meal_template('0192f000-0000-7000-8000-0000000002b1', repeat('a', 61), '[{"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "katori"}]', NULL)$$,
    '22023', NULL, 'saved meal names are at most 60 characters'
);
SELECT
    throws_ok(
        format(
            $$CALL nutrition.pr_save_meal_template('0192f000-0000-7000-8000-0000000002b1', %L, '[{"food_id": "0192f000-0000-7000-8000-000000000004", "quantity": 1, "unit_code": "katori"}]', NULL)$$,
            payload
        ),
        '22023', NULL, format('payload #%s rejected as a saved meal name', id)
    )
FROM test_payloads
WHERE char_length(btrim(payload)) BETWEEN 1 AND 60
ORDER BY id;
DO $$
DECLARE v uuid;
BEGIN
    FOR n IN 1..49 LOOP
        CALL nutrition.pr_save_meal_template('0192f000-0000-7000-8000-0000000002b1', 'Meal ' || n,
            '[{"food_id": "0192f000-0000-7000-8000-000000000002", "quantity": 1, "unit_code": "piece"}]', v);
    END LOOP;
END
$$;
SELECT throws_ok(
    $$CALL nutrition.pr_save_meal_template('0192f000-0000-7000-8000-0000000002b1', 'One too many', '[{"food_id": "0192f000-0000-7000-8000-000000000002", "quantity": 1, "unit_code": "piece"}]', NULL)$$,
    'P0001', NULL, 'at most 50 saved meals (SAVED_MEAL_LIMIT)'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b2', TRUE);
SELECT throws_ok(
    format($$CALL nutrition.pr_delete_saved_meal('0192f000-0000-7000-8000-0000000002b2', %L)$$, (SELECT id FROM sm)),
    '42501', NULL, 'another user''s saved meal cannot be deleted'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000002b1', TRUE);
SELECT lives_ok(
    format($$CALL nutrition.pr_delete_saved_meal('0192f000-0000-7000-8000-0000000002b1', %L)$$, (SELECT id FROM sm)),
    'own saved meal deleted'
);
SELECT is((SELECT count(*)::integer FROM nutrition.fn_saved_meals('0192f000-0000-7000-8000-0000000002b1')), 49, 'deleted saved meals are not listed');

SELECT * FROM finish();
ROLLBACK;
