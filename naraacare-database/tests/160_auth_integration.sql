-- Routines added for the Session 05 API: resend lookup, password rehash, Apple token storage, calc
-- context, current policies and current consents.
BEGIN;
SELECT no_plan();

CREATE TEMP TABLE r (k text PRIMARY KEY, v text);
CREATE FUNCTION pg_temp.v(p_key text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM r WHERE k = p_key $$;
CREATE FUNCTION pg_temp.h(p_n integer) RETURNS text LANGUAGE sql
AS $$ SELECT '$argon2id$v=19$m=16384,t=2,p=1$c2FsdHNhbHQ$aGFzaA' || p_n $$;
CREATE FUNCTION pg_temp.b(p_hex text) RETURNS bytea LANGUAGE sql AS $$ SELECT decode(repeat(p_hex, 32), 'hex') $$;
CREATE FUNCTION pg_temp.e(p_tag text) RETURNS text LANGUAGE sql AS $$ SELECT 'u' || p_tag || '@example.test' $$;
CREATE FUNCTION pg_temp.i(p_hex text) RETURNS uuid LANGUAGE sql
AS $$ SELECT ('00000000-0000-7000-8000-0000000000' || p_hex)::uuid $$;
CREATE FUNCTION pg_temp.otp(p_n integer) RETURNS text LANGUAGE sql AS $$ SELECT lpad(p_n::text, 6, '0') $$;

-- ===== auth.fn_otp_challenge_email =====
DO $$
DECLARE u uuid; c uuid; s text; w integer;
BEGIN
    CALL auth.pr_create_account(pg_temp.e('e7'), pg_temp.h(1), pg_temp.i('f7'), pg_temp.otp(100), u, c, s, w);
    INSERT INTO r VALUES ('u', u), ('c', c);
END $$;
SELECT is(
    (SELECT email::text FROM auth.fn_otp_challenge_email(pg_temp.v('c')::uuid)),
    pg_temp.e('e7'),
    'resend lookup returns the account email'
);
SELECT is(
    (SELECT purpose::text FROM auth.fn_otp_challenge_email(pg_temp.v('c')::uuid)),
    'email_verification',
    'and the challenge purpose'
);
UPDATE auth.otp_challenge SET consumed_at = now()
WHERE id = pg_temp.v('c')::uuid;
SELECT is(
    (SELECT count(*)::int FROM auth.fn_otp_challenge_email(pg_temp.v('c')::uuid)), 0,
    'a consumed challenge returns nothing'
);
SELECT is(
    (SELECT count(*)::int FROM auth.fn_otp_challenge_email('0192f000-0000-7000-8000-00000000ffff')), 0,
    'an unknown challenge returns nothing'
);

-- ===== auth.pr_rehash_password =====
SELECT set_config('app.user_id', pg_temp.v('u'), TRUE);
DO $$
DECLARE ok boolean;
BEGIN
    CALL auth.pr_rehash_password(pg_temp.v('u')::uuid, pg_temp.h(1), pg_temp.h(9), ok);
    INSERT INTO r VALUES ('rehash1', ok);
    CALL auth.pr_rehash_password(pg_temp.v('u')::uuid, pg_temp.h(1), pg_temp.h(8), ok);
    INSERT INTO r VALUES ('rehash2', ok);
END $$;
SELECT is(pg_temp.v('rehash1'), 'true', 'rehash replaces the hash when the old one matches');
SELECT is(pg_temp.v('rehash2'), 'false', 'compare-and-swap: a stale old hash changes nothing');
SELECT is(
    (
        SELECT password_hash::text FROM auth.user_account
        WHERE id = pg_temp.v('u')::uuid
    ), pg_temp.h(9
    ),
    'the new hash is stored'
);
SELECT is(
    (
        SELECT count(*)::int FROM auth.password_history
        WHERE user_id = pg_temp.v('u')::uuid
    ), 1,
    'rehashing does not add to the password history'
);
SELECT throws_ok(
    $$CALL auth.pr_rehash_password('0192f000-0000-7000-8000-00000000fffe', NULL, NULL, NULL)$$,
    '42501', NULL, 'rehash is limited to the actor'
);

-- ===== auth.pr_store_provider_token =====
DO $$
DECLARE u uuid; s text;
BEGIN
    CALL auth.pr_create_oauth_account('apple', 'sub-a1', pg_temp.e('e8'), pg_temp.i('f8'), u, s);
    INSERT INTO r VALUES ('apple_user', u);
END $$;
SELECT set_config('app.user_id', pg_temp.v('apple_user'), TRUE);
DO $$
DECLARE ok boolean;
BEGIN
    CALL auth.pr_store_provider_token(pg_temp.v('apple_user')::uuid, 'apple', 'sub-a1', 'r99.0.apple-token', ok);
    INSERT INTO r VALUES ('stored', ok);
    CALL auth.pr_store_provider_token(pg_temp.v('apple_user')::uuid, 'apple', 'sub-a2', 'r99.0.apple-token', ok);
    INSERT INTO r VALUES ('stored_other', ok);
END $$;
SELECT is(pg_temp.v('stored'), 'true', 'the Apple refresh token is stored on the actor''s link');
SELECT is(pg_temp.v('stored_other'), 'false', 'an unknown subject updates nothing');
SELECT is(
    (
        SELECT provider_refresh_token::text FROM auth.identity_link
        WHERE user_id = pg_temp.v('apple_user')::uuid
    ),
    'r99.0.apple-token',
    'stored in plain text'
);
SELECT throws_ok(
    format(
        $$CALL auth.pr_store_provider_token(%L, 'apple', 'sub-a1', 'r99.0.apple-token', NULL)$$,
        pg_temp.v('u')
    ),
    '42501', NULL, 'another user''s link cannot be written'
);

-- ===== ref.fn_calc_context =====
SELECT is(ref.fn_calc_context() ->> 'calc_version', '2026.1', 'calc context names the version in force');
SELECT is((ref.fn_calc_context() -> 'constants' ->> 'nutr.floor.female_kcal')::numeric, 1200::numeric, 'constants are included');
SELECT is(
    (ref.fn_calc_context() -> 'activity_levels' -> 'moderately_active' ->> 'tdee_multiplier')::numeric, 1.02,
    'activity multiplier'
);
SELECT is(
    (ref.fn_calc_context() -> 'activity_levels' -> 'moderately_active' ->> 'activity_number')::numeric, 1.85,
    'joined with the hydration activity number (OQ-13)'
);
SELECT is((ref.fn_calc_context() -> 'body_types' ->> 'endomorph')::numeric, 1.03, 'body-type factor');
SELECT is((ref.fn_calc_context() -> 'weight_goals' -> 'standard_gain' ->> 'kcal_delta')::int, 500, 'goal delta');
SELECT is(jsonb_array_length(ref.fn_calc_context() -> 'bmi_categories'), 3, 'three BMI categories');
SELECT ok(ref.fn_calc_context() -> 'medical_condition_codes' ? 'diabetes', 'medical condition codes listed');
SELECT ok(ref.fn_calc_context() -> 'avatar_codes' ? 'female_mesomorph', 'avatar codes listed');

-- ===== ref.fn_policies =====
SELECT is(
    (SELECT array_agg(doc_type::text ORDER BY doc_type) FROM ref.fn_policies()),
    ARRAY['licenses', 'privacy', 'terms'],
    'one current row per policy type'
);
INSERT INTO ref.policy_document (doc_type, version, url, published_at)
VALUES ('terms', '1.0', 'https://naraacare.app/terms/1.0', now()), ('terms', '1.1-draft', 'https://naraacare.app/terms/1.1', NULL);
SELECT is(
    (
        SELECT version::text FROM ref.fn_policies()
        WHERE doc_type = 'terms'
    ), '1.0',
    'a published version wins over a newer draft'
);

-- ===== privacy.fn_current_consents =====
SELECT set_config('app.user_id', pg_temp.v('apple_user'), TRUE);
DO $$
DECLARE id bigint;
BEGIN
    CALL privacy.pr_record_consent(pg_temp.v('apple_user')::uuid, 'ai_processing', '0.0-draft', TRUE, NULL, NULL, id);
    CALL privacy.pr_record_consent(pg_temp.v('apple_user')::uuid, 'marketing', '0.0-draft', TRUE, NULL, NULL, id);
END $$;
-- consent_record is append-only and now() is fixed in this transaction, so the newer row wins on id.
DO $$
DECLARE id bigint;
BEGIN
    CALL privacy.pr_record_consent(pg_temp.v('apple_user')::uuid, 'ai_processing', '0.0-draft', FALSE, NULL, NULL, id);
END $$;
SELECT is(
    (
        SELECT granted FROM privacy.fn_current_consents(pg_temp.v('apple_user')::uuid)
        WHERE purpose = 'ai_processing'
    ),
    FALSE,
    'the latest decision per purpose wins (withdrawal)'
);
SELECT is(
    (SELECT count(*)::int FROM privacy.fn_current_consents(pg_temp.v('apple_user')::uuid)), 2,
    'one row per answered purpose'
);
SELECT throws_ok(
    format($$SELECT * FROM privacy.fn_current_consents(%L)$$, pg_temp.v('u')),
    '42501', NULL, 'consents of another user are not readable'
);

SELECT * FROM finish();
ROLLBACK;
