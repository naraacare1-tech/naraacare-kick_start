-- Workouts: STAR only, sweat/kcal snapshots, nutrition allowance and hydration sweat in the same
-- transaction, idempotency, delete window and IDOR (Session 09; doc 06 sections 2.7 and 3.4, OQ-16, OQ-58).
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000003d1', 'ud1@example.test', 'active'),
('0192f000-0000-7000-8000-0000000003d2', 'ud2@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at)
VALUES ('0192f000-0000-7000-8000-0000000003d1', 6, now()), ('0192f000-0000-7000-8000-0000000003d2', 6, now());
INSERT INTO app.health_target_snapshot (
    user_id, effective_date, calc_version, inputs, bmi, bmi_category, bmr_kcal, tdee_kcal, goal_delta_kcal,
    calculated_target_kcal, base_target_kcal, safety_override, carbs_g, fat_g, protein_g,
    lean_body_weight_kg, water_movement_ml, base_water_need_ml
)
SELECT
    u,
    current_date - 30,
    '2026.1',
    '{"sex": "male", "age_years": 28, "height_cm": 175, "weight_kg": 80, "body_type": "mesomorph", "activity_level": "very_active"}',
    26.1,
    'overweight_obese',
    1754,
    1877,
    0,
    1877,
    1877,
    FALSE,
    258,
    52,
    94,
    60.09,
    4761,
    4047
FROM unnest(ARRAY['0192f000-0000-7000-8000-0000000003d1'::uuid, '0192f000-0000-7000-8000-0000000003d2'::uuid]) AS u;
-- d1 is STAR, d2 STANDARD.
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-0000000003d1', 'star', 'promo', now() - interval '1 day', now() + interval '30 days');

CREATE FUNCTION pg_temp.workout(p_user uuid, p_id uuid, p_at timestamptz, p_type text, p_min integer)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s text; d date;
BEGIN
    CALL activity.pr_log_workout(p_user, p_id, p_at, p_type, p_min, s, d);
    RETURN s;
END
$$;
CREATE FUNCTION pg_temp.id(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(12288 + n), 12, '0'))::uuid
$$;
CREATE FUNCTION pg_temp.at(p_hours numeric) RETURNS timestamptz LANGUAGE sql AS $$
    SELECT ((common.fn_local_date('Asia/Kolkata') - 1)::timestamp + p_hours * interval '1 hour') AT TIME ZONE 'Asia/Kolkata'
$$;
CREATE FUNCTION pg_temp.yday() RETURNS date LANGUAGE sql AS $$ SELECT common.fn_local_date('Asia/Kolkata') - 1 $$;

SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003d2', TRUE);
SELECT throws_ok(
    $$SELECT pg_temp.workout('0192f000-0000-7000-8000-0000000003d2', pg_temp.id(1), pg_temp.at(7), 'running', 60)$$,
    'P0001', 'workouts need STAR', 'STANDARD cannot log workouts (OQ-04)'
);

SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003d1', TRUE);
SELECT is(pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(1), pg_temp.at(7), 'running', 60), 'created', 'a 60-minute run is saved');
SELECT is(
    (
        SELECT row(sweat_ml, kcal, calc_version)::text FROM activity.workout
        WHERE id = pg_temp.id(1)
    ),
    '(1000.0,784,2026.1)', 'Sahil: 12.5 x 80 x 1 h = 1,000 mL sweat; 9.8 x 80 x 1 h = 784 kcal (doc 06)'
);
SELECT is(pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(1), pg_temp.at(7), 'running', 60), 'duplicate', 'a replay changes nothing');
SELECT is(pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(2), pg_temp.at(18), 'walking', 45), 'created', 'a second workout the same day (OQ-58)');
SELECT is(
    (
        SELECT row(sweat_ml, kcal)::text FROM activity.workout
        WHERE id = pg_temp.id(2)
    ),
    '(300.0,210)', 'walking 45 min: 5 x 80 x 0.75 = 300 mL; 3.5 x 80 x 0.75 = 210 kcal'
);
SELECT is(
    (
        SELECT row(exercise_kcal, base_target_kcal, effective_allowance_kcal)::text FROM nutrition.daily_summary
        WHERE user_id = '0192f000-0000-7000-8000-0000000003d1' AND local_date = pg_temp.yday()
    ),
    '(994,1877,2871)', 'nutrition: exercise kcal add up and raise the allowance (doc 06 section 2.7)'
);
SELECT is(
    (
        SELECT workout_sweat_ml FROM hydration.daily_summary
        WHERE user_id = '0192f000-0000-7000-8000-0000000003d1' AND local_date = pg_temp.yday()
    ),
    1300.0, 'hydration: workout sweat adds up'
);
SELECT is(
    (SELECT jsonb_array_length(hydration.fn_day_inputs('0192f000-0000-7000-8000-0000000003d1', pg_temp.yday()) -> 'workouts')),
    2, 'day inputs carry both workouts'
);
SELECT ok(
    (
        SELECT has_hydration FROM app.user_activity_day
        WHERE user_id = '0192f000-0000-7000-8000-0000000003d1' AND local_date = pg_temp.yday()
    ),
    'a workout marks the day active'
);

SELECT throws_ok($$SELECT pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(3), pg_temp.at(9), 'running', 0)$$, '22023', NULL, '0 minutes is refused');
SELECT throws_ok($$SELECT pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(3), pg_temp.at(9), 'running', 601)$$, '22023', NULL, 'more than 600 minutes is refused');
SELECT throws_ok($$SELECT pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(3), pg_temp.at(9), 'yoga', 30)$$, '22023', NULL, 'an unknown workout type is refused');
SELECT throws_ok($$SELECT pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(3), now() + interval '1 hour', 'gym', 30)$$, '22023', NULL, 'a future workout is refused');
SELECT throws_ok($$SELECT pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(3), now() - interval '9 days', 'gym', 30)$$, 'P0001', NULL, 'older than 7 days is refused');

SELECT is(
    (SELECT string_agg(workout_type || ':' || editable, ',' ORDER BY performed_at) FROM activity.fn_workouts('0192f000-0000-7000-8000-0000000003d1', pg_temp.yday())),
    'running:true,walking:true', 'workouts listed with the delete flag'
);
SELECT throws_ok(
    format($$CALL activity.pr_delete_workout('0192f000-0000-7000-8000-0000000003d1', %L, 7)$$, pg_temp.id(2)),
    'P0001', 'workout was changed elsewhere', 'a stale version is refused'
);
SELECT lives_ok(
    format($$CALL activity.pr_delete_workout('0192f000-0000-7000-8000-0000000003d1', %L, 1)$$, pg_temp.id(2)),
    'the walk is deleted'
);
SELECT
    is(
        (
            SELECT row(n.exercise_kcal, n.effective_allowance_kcal, h.workout_sweat_ml)::text
            FROM nutrition.daily_summary AS n
            INNER JOIN hydration.daily_summary AS h ON n.user_id = h.user_id AND n.local_date = h.local_date
        WHERE n.user_id = '0192f000-0000-7000-8000-0000000003d1' AND n.local_date = pg_temp.yday()
    ),
    '(784,2661,1000.0)', 'both summaries are rebuilt after the delete'
);
SELECT is(pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(4), pg_temp.at(19), 'gym', 30), 'created', 'gym');
SELECT is(pg_temp.workout('0192f000-0000-7000-8000-0000000003d1', pg_temp.id(5), pg_temp.at(20), 'cycling', 30), 'created', 'cycling');
SELECT throws_ok(
format($$CALL activity.pr_delete_workout('0192f000-0000-7000-8000-0000000003d1', %L, 1)$$, pg_temp.id(1)),
'P0001', 'only the last 2 workouts within 7 days can be deleted', 'the 3rd-last workout cannot be deleted'
);

-- IDOR
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003d2', TRUE);
SELECT throws_ok(
format($$CALL activity.pr_delete_workout('0192f000-0000-7000-8000-0000000003d2', %L, 1)$$, pg_temp.id(5)),
'42501', NULL, 'another user''s workout cannot be deleted (404)'
);
SELECT is(
(SELECT count(*)::integer FROM activity.fn_workouts('0192f000-0000-7000-8000-0000000003d2', NULL, pg_temp.id(5))),
0, 'another user''s workout is not readable'
);
SELECT throws_ok(
$$SELECT * FROM activity.fn_workouts('0192f000-0000-7000-8000-0000000003d1', current_date)$$,
'42501', NULL, 'nobody can list another user''s workouts'
);

SELECT ok(NOT has_function_privilege('app_rw', 'activity.fn_editable_workout_ids(uuid)', 'EXECUTE'), 'internal helper not granted');
SELECT ok(NOT has_function_privilege('app_rw', 'activity.pr_refresh_workout_totals(uuid, date)', 'EXECUTE'), 'internal rebuild not granted');

SELECT * FROM finish();
ROLLBACK;
