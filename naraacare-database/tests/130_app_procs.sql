-- Profile, onboarding, username, settings, entitlement and reference procedures (Session 03).
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

CREATE TEMP TABLE r (k text PRIMARY KEY, v text);
CREATE FUNCTION pg_temp.v(p_key text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM r WHERE k = p_key $$;
-- A valid snapshot as the API would compute it (values only need to satisfy the table CHECKs here).
CREATE FUNCTION pg_temp.snap(p_kcal integer) RETURNS jsonb LANGUAGE sql AS $$
    SELECT jsonb_build_object(
        'calc_version', '2026.1', 'inputs', '{"weight_kg": 70}'::jsonb, 'bmi', 22.9, 'bmi_category', 'normal',
        'bmr_kcal', 1600, 'tdee_kcal', 2200, 'goal_delta_kcal', -500, 'calculated_target_kcal', p_kcal,
        'base_target_kcal', p_kcal, 'safety_override', FALSE, 'carbs_g', 235, 'fat_g', 47, 'protein_g', 85,
        'lean_body_weight_kg', 55.2, 'water_movement_ml', 3200.5, 'base_water_need_ml', 2700
    )
$$;

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000000d1', 'ud1@example.test', 'active'),
('0192f000-0000-7000-8000-0000000000d2', 'ud2@example.test', 'active');
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000000d1', TRUE);

-- ===== Onboarding =====
SELECT throws_ok(
    $$CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 2::smallint, p_height_cm => 170)$$,
    '22023', NULL, 'steps cannot be skipped'
);
SELECT throws_ok(
    $$CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 1::smallint, p_biological_sex => 'female')$$,
    '22023', NULL, 'a step without its required fields is rejected'
);
SELECT throws_ok(
    $$CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 7::smallint)$$,
    '22023', NULL, 'step must be 1..6'
);
SELECT throws_ok(
    $$CALL app.pr_complete_onboarding('0192f000-0000-7000-8000-0000000000d1', '{}', '[]')$$,
    'P0001', NULL, 'cannot complete before all steps are saved'
);
SELECT lives_ok(
    $$
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 1::smallint,
        p_biological_sex => 'female', p_avatar_code => 'female_mesomorph', p_full_name => 'Asha Rao');
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 2::smallint, p_height_cm => 165.5);
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 3::smallint,
        p_weight_kg => 62.25, p_weight_goal_code => 'standard_loss');
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 4::smallint, p_target_weight_kg => 58);
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 5::smallint,
        p_age_years => 30::smallint, p_activity_level_code => 'lightly_active');
    $$,
    'steps 1-5 save in order'
);
SELECT throws_ok(
    $$CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 6::smallint, p_body_type_code => 'triangle')$$,
    '23503', NULL, 'unknown codes are rejected by the reference FK'
);
SELECT throws_ok(
    $$CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 2::smallint, p_height_cm => 300)$$,
    '23514', NULL, 'out-of-range values are rejected by the table CHECK'
);
DO $$
DECLARE s smallint;
BEGIN
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 6::smallint, p_body_type_code => 'mesomorph', o_current_step => s);
    INSERT INTO r VALUES ('step', s);
    CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 2::smallint, p_height_cm => 166, o_current_step => s);
    INSERT INTO r VALUES ('step_revisit', s);
END $$;
SELECT is(pg_temp.v('step'), '6', 'step 6 saved');
SELECT is(pg_temp.v('step_revisit'), '6', 'revisiting an earlier step keeps the progress');

SELECT throws_ok(
    $$CALL app.pr_complete_onboarding('0192f000-0000-7000-8000-0000000000d1', pg_temp.snap(1700),
      '[{"purpose": "health_data", "policy_version": "0.0-draft", "granted": false}]')$$,
    'P0001', NULL, 'health_data consent is required (CONSENT_REQUIRED)'
);
SELECT throws_ok(
    $$CALL app.pr_complete_onboarding('0192f000-0000-7000-8000-0000000000d1', pg_temp.snap(1700), '{"purpose": "x"}')$$,
    '22023', NULL, 'consents must be a list'
);
SELECT throws_ok(
    $$CALL app.pr_complete_onboarding('0192f000-0000-7000-8000-0000000000d1', pg_temp.snap(1700) || '{"evil": 1}',
      '[{"purpose": "health_data", "policy_version": "0.0-draft", "granted": true}]')$$,
    '22023', NULL, 'unknown snapshot fields are rejected'
);
SELECT throws_ok(
    $$CALL app.pr_complete_onboarding('0192f000-0000-7000-8000-0000000000d1', pg_temp.snap(1700),
      '[{"purpose": "terms", "policy_version": "9.9", "granted": true},
        {"purpose": "health_data", "policy_version": "0.0-draft", "granted": true}]')$$,
    '22023', NULL, 'terms consent must name a published policy version'
);
SELECT lives_ok(
    $$CALL app.pr_complete_onboarding('0192f000-0000-7000-8000-0000000000d1', pg_temp.snap(1700),
      '[{"purpose": "terms", "policy_version": "0.0-draft", "granted": true},
        {"purpose": "privacy", "policy_version": "0.0-draft", "granted": true},
        {"purpose": "health_data", "policy_version": "0.0-draft", "granted": true},
        {"purpose": "marketing", "policy_version": "0.0-draft", "granted": false}]', '1.0.0')$$,
    'onboarding completes with consents and a snapshot'
);
SELECT results_eq(
    $$SELECT onboarding_completed_at IS NOT NULL, sleep_goal_min::int FROM app.user_profile
      WHERE user_id = '0192f000-0000-7000-8000-0000000000d1'$$,
    $$VALUES (TRUE, 480)$$,
    'onboarding marked complete; sleep goal defaulted from age (30 -> 480 min)'
);
SELECT is(
    (
        SELECT count(*)::int FROM privacy.consent_record
        WHERE user_id = '0192f000-0000-7000-8000-0000000000d1'
    ), 4,
    'one consent row per purpose'
);
SELECT is(
    (
        SELECT policy_document_id IS NOT NULL FROM privacy.consent_record
        WHERE user_id = '0192f000-0000-7000-8000-0000000000d1' AND purpose = 'terms'
    ),
    TRUE, 'terms consent points at the policy document'
);
SELECT throws_ok(
    $$CALL app.pr_save_onboarding_step('0192f000-0000-7000-8000-0000000000d1', 2::smallint, p_height_cm => 170)$$,
    'P0001', NULL, 'onboarding steps are closed after completion'
);

-- ===== Profile update: today's snapshot replaced, past days untouched =====
INSERT INTO app.health_target_snapshot (
    user_id, effective_date, calc_version, inputs, bmi, bmi_category, bmr_kcal, tdee_kcal, goal_delta_kcal,
    calculated_target_kcal, base_target_kcal, safety_override, carbs_g, fat_g, protein_g,
    lean_body_weight_kg, water_movement_ml, base_water_need_ml
)
VALUES (
    '0192f000-0000-7000-8000-0000000000d1', common.fn_local_date('Asia/Kolkata') - 10, '2026.1', '{}', 22, 'normal',
    1600, 2200, -500, 1650, 1650, FALSE, 220, 45, 80, 55, 3200, 2600
);
SELECT lives_ok(
    $$CALL app.pr_update_profile('0192f000-0000-7000-8000-0000000000d1', p_weight_kg => 61, p_snapshot => pg_temp.snap(1750))$$,
    'profile update with a new snapshot'
);
SELECT results_eq(
    $$SELECT effective_date - common.fn_local_date('Asia/Kolkata'), base_target_kcal
      FROM app.health_target_snapshot WHERE user_id = '0192f000-0000-7000-8000-0000000000d1' ORDER BY effective_date$$,
    $$VALUES (-10, 1650), (0, 1750)$$,
    'today''s snapshot replaced (1700 -> 1750); the past day keeps 1650'
);
SELECT is(
    (SELECT base_target_kcal FROM app.fn_latest_target_snapshot('0192f000-0000-7000-8000-0000000000d1')), 1750,
    'fn_latest_target_snapshot returns today''s targets'
);
SELECT is(
    (SELECT base_target_kcal FROM app.fn_latest_target_snapshot(
        '0192f000-0000-7000-8000-0000000000d1', common.fn_local_date('Asia/Kolkata') - 5
    )),
    1650, 'a past day gets the targets in force then'
);
SELECT results_eq(
    $$SELECT weight_kg, height_cm FROM app.user_profile WHERE user_id = '0192f000-0000-7000-8000-0000000000d1'$$,
    $$VALUES (61.00::numeric(5, 2), 166.0::numeric(4, 1))$$,
    'only the given fields change'
);

-- ===== Username =====
SELECT ok(app.fn_username_available('priya.s'), 'free username is available');
SELECT lives_ok(
    $$CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d1', 'priya.s')$$, 'first username set'
);
SELECT ok(app.fn_username_available('priya.s'), 'own username counts as available to its owner');
SELECT throws_ok(
    $$CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d1', 'priya.sharma')$$,
    'P0001', NULL, 'second change within 90 days -> USERNAME_CHANGE_TOO_SOON'
);
UPDATE app.user_profile SET username_changed_at = now() - interval '91 days'
WHERE user_id = '0192f000-0000-7000-8000-0000000000d1';
SELECT lives_ok(
    $$CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d1', 'priya.sharma')$$, 'change allowed after 90 days'
);
SELECT throws_ok(
    $$CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d1', 'Priya.Sharma')$$,
    '23514', NULL, 'upper case is rejected by the username domain (uniqueness is case-insensitive by construction)'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000000d2', TRUE);
CALL app.pr_save_onboarding_step(
    '0192f000-0000-7000-8000-0000000000d2', 1::smallint,
    p_biological_sex => 'male', p_avatar_code => 'male_mesomorph', p_full_name => 'Asha Rao'
);
SELECT ok(NOT app.fn_username_available('priya.sharma'), 'another user''s username is not available (crosses RLS)');
SELECT throws_ok(
    $$CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d2', 'priya.sharma')$$,
    'P0001', NULL, 'duplicate username -> USERNAME_TAKEN'
);
SELECT throws_ok(
    $$CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d1', 'other.name')$$,
    '42501', NULL, 'actor mismatch -> 42501'
);
SELECT throws_ok(
    $$SELECT * FROM app.fn_get_profile('0192f000-0000-7000-8000-0000000000d1')$$,
    '42501', NULL, 'cannot read another user''s profile'
);

-- ===== Settings =====
SELECT lives_ok(
    $$CALL app.pr_update_settings('0192f000-0000-7000-8000-0000000000d2', 'ft_in', 'lb', 'f', 'Europe/London', 'en-GB',
      '22:30', '06:30', TRUE)$$,
    'settings saved'
);
SELECT results_eq(
    $$SELECT height_unit::text, timezone::text, biometric_lock, onboarding_step::int
      FROM app.fn_get_profile('0192f000-0000-7000-8000-0000000000d2')$$,
    $$VALUES ('ft_in', 'Europe/London', TRUE, 1)$$,
    'fn_get_profile returns the settings and onboarding state'
);
SELECT throws_ok(
    $$CALL app.pr_update_settings('0192f000-0000-7000-8000-0000000000d2', 'cm', 'kg', 'c', 'Mars/Olympus_Mons', 'en',
      '22:30', '06:30', FALSE)$$,
    '22023', NULL, 'a well-formed but unknown timezone is rejected'
);
SELECT throws_ok(
    $$CALL app.pr_update_settings('0192f000-0000-7000-8000-0000000000d2', 'cm', 'kg', 'c', 'Asia/Kolkata', 'en',
      '22:30', '22:30', FALSE)$$,
    '23514', NULL, 'sleep start equal to wake time is rejected'
);

-- ===== Payloads through every text-accepting parameter =====
DO $payloads$
DECLARE
    r record;
    v_accepted integer := 0;
    v_id bigint;
BEGIN
    FOR r IN SELECT payload FROM test_payloads LOOP
        BEGIN
            CALL app.pr_set_username('0192f000-0000-7000-8000-0000000000d2', r.payload::common.username);
            v_accepted := v_accepted + 1;
        EXCEPTION WHEN check_violation OR invalid_parameter_value OR string_data_right_truncation THEN NULL;
        END;
        BEGIN
            CALL app.pr_update_settings('0192f000-0000-7000-8000-0000000000d2', 'cm', 'kg', 'c',
                r.payload::common.iana_timezone, 'en', '22:00', '06:00', FALSE);
            v_accepted := v_accepted + 1;
        EXCEPTION WHEN check_violation OR invalid_parameter_value THEN NULL;
        END;
        BEGIN
            CALL app.pr_update_settings('0192f000-0000-7000-8000-0000000000d2', 'cm', 'kg', 'c',
                'Asia/Kolkata', r.payload::common.locale, '22:00', '06:00', FALSE);
            v_accepted := v_accepted + 1;
        EXCEPTION WHEN check_violation OR invalid_parameter_value THEN NULL;
        END;
        BEGIN
            CALL privacy.pr_record_consent('0192f000-0000-7000-8000-0000000000d2', 'marketing',
                r.payload::common.version_label, TRUE, NULL, NULL, v_id);
            v_accepted := v_accepted + 1;
        EXCEPTION WHEN check_violation OR invalid_parameter_value THEN NULL;
        END;
        BEGIN
            CALL privacy.pr_record_consent('0192f000-0000-7000-8000-0000000000d2', r.payload::common.code,
                '0.0-draft', TRUE, NULL, NULL, v_id);
            v_accepted := v_accepted + 1;
        EXCEPTION WHEN check_violation OR invalid_parameter_value THEN NULL;
        END;
        BEGIN
            PERFORM app.fn_username_available(r.payload::common.username);
            v_accepted := v_accepted + 1;
        EXCEPTION WHEN check_violation THEN NULL;
        END;
    END LOOP;
    CREATE TEMP TABLE app_payload_result AS SELECT v_accepted AS accepted;
END
$payloads$;
SELECT is(
    (SELECT accepted FROM app_payload_result), 0,
    'all 529 payloads rejected by username, timezone, locale, policy version, purpose and availability parameters'
);

-- ===== Entitlement =====
SELECT results_eq(
    $$SELECT tier_code::text, source::text, expires_at, features ->> 'sleep', limits ->> 'meal_logs_per_day'
      FROM billing.fn_current_entitlement('0192f000-0000-7000-8000-0000000000d2')$$,
    $$VALUES ('standard', 'default', NULL::timestamptz, 'false', '4')$$,
    'no subscription or grant -> STANDARD with its limits'
);
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-0000000000d2', 'star', 'referral', now() - interval '1 day', now() + interval '30 days');
SELECT results_eq(
    $$SELECT tier_code::text, source::text, expires_at, features ->> 'sleep', limits ->> 'meal_logs_per_day'
      FROM billing.fn_current_entitlement('0192f000-0000-7000-8000-0000000000d2')$$,
    $$VALUES ('star', 'referral', now() + interval '30 days', 'true', '8')$$,
    'active referral grant -> STAR'
);
INSERT INTO billing.subscription (
    user_id, platform, product_id, purchase_token, status, auto_renew,
    current_period_start, current_period_end, environment, last_verified_at
) VALUES (
    '0192f000-0000-7000-8000-0000000000d2', 'google_play', 'star_monthly', 'play-token-5d', 'active', TRUE,
    now() - interval '1 day', now() + interval '29 days', 'sandbox', now()
);
SELECT results_eq(
    $$SELECT tier_code::text, source::text FROM billing.fn_current_entitlement('0192f000-0000-7000-8000-0000000000d2')$$,
    $$VALUES ('star', 'store')$$,
    'an active store subscription is preferred as the source'
);
UPDATE billing.subscription SET status = 'expired'
WHERE user_id = '0192f000-0000-7000-8000-0000000000d2';
UPDATE billing.entitlement_grant SET ends_at = now() - interval '1 second', starts_at = now() - interval '2 days'
WHERE user_id = '0192f000-0000-7000-8000-0000000000d2';
SELECT is(
    (SELECT tier_code::text FROM billing.fn_current_entitlement('0192f000-0000-7000-8000-0000000000d2')), 'standard',
    'expired subscription and grant -> back to STANDARD'
);
SELECT throws_ok(
    $$SELECT * FROM billing.fn_current_entitlement('0192f000-0000-7000-8000-0000000000d1')$$,
    '42501', NULL, 'cannot read another user''s entitlement'
);

-- ===== Reference bootstrap =====
SELECT results_eq(
    $$SELECT jsonb_array_length(payload -> 'nutrients'), jsonb_array_length(payload -> 'drinks'),
             jsonb_array_length(payload -> 'avatars'), payload ->> 'calc_version'
      FROM ref.fn_bootstrap()$$,
    $$VALUES (17, 7, 6, '2026.1')$$,
    'bootstrap carries the reference lists'
);
SELECT ok(
    (SELECT etag ~ '^[0-9a-f]{64}$' AND etag = encode(sha256(convert_to(payload::text, 'UTF8')), 'hex') FROM ref.fn_bootstrap()),
    'ETag is the SHA-256 of the payload'
);
SELECT is(
    (SELECT etag FROM ref.fn_bootstrap()), (SELECT etag FROM ref.fn_bootstrap()), 'ETag is stable between calls'
);

SELECT * FROM finish();
ROLLBACK;
