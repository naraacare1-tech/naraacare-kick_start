-- Auth procedures (doc 07 SEC-1.2, SEC-1.3, SEC-1.6). Time is simulated by moving timestamps back,
-- because now() is fixed inside the test transaction.
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

-- ===== Sign-up and OTP =====
DO $$
DECLARE u uuid; c uuid; s text; w integer;
BEGIN
    CALL auth.pr_create_account(pg_temp.e('e1'), pg_temp.h(1), pg_temp.i('f1'), pg_temp.otp(100), u, c, s, w);
    INSERT INTO r VALUES ('u1', u), ('c1', c), ('s1', s);
    CALL auth.pr_create_account(pg_temp.e('e1'), pg_temp.h(2), pg_temp.i('f1'), pg_temp.otp(101), u, c, s, w);
    INSERT INTO r VALUES ('s_again', s), ('w_again', w);
END $$;
SELECT is(pg_temp.v('s1'), 'ok', 'sign-up creates the account and a challenge');
SELECT is(
    (
        SELECT status::text FROM auth.user_account
        WHERE id = pg_temp.v('u1')::uuid
    ), 'pending_verification',
    'new account is pending verification'
);
SELECT is(
    (
        SELECT count(*)::int FROM auth.password_history
        WHERE user_id = pg_temp.v('u1')::uuid
    ), 1,
    'first password goes into the history'
);
SELECT is(pg_temp.v('s_again'), 'rate_limited', 'repeating sign-up within 30 s is rate limited');
SELECT ok(pg_temp.v('w_again')::int BETWEEN 1 AND 30, 'retry_after is within the 30 s cooldown');
SELECT is(
    (
        SELECT password_hash::text FROM auth.user_account
        WHERE id = pg_temp.v('u1')::uuid
    ), pg_temp.h(1
    ),
    'a rate-limited repeat sign-up changes nothing'
);

UPDATE auth.otp_challenge SET last_sent_at = now() - interval '31 seconds', created_at = now() - interval '31 seconds';
DO $$
DECLARE u uuid; c uuid; s text; w integer;
BEGIN
    CALL auth.pr_create_account(pg_temp.e('e1'), pg_temp.h(2), pg_temp.i('f1'), pg_temp.otp(102), u, c, s, w);
    INSERT INTO r VALUES ('c2', c), ('s2', s), ('u2', u);
END $$;
SELECT is(pg_temp.v('s2'), 'ok', 'repeat sign-up after the cooldown issues a new challenge');
SELECT is(pg_temp.v('u2'), pg_temp.v('u1'), 'same pending account is reused');
SELECT is(
    (
        SELECT attempts::int FROM auth.otp_challenge
        WHERE id = pg_temp.v('c1')::uuid
    ), 3,
    'the older challenge is dead (only the newest code works)'
);
SELECT is(
    (
        SELECT array_agg(password_hash::text) FROM auth.password_history
        WHERE user_id = pg_temp.v('u1')::uuid
    ),
    ARRAY[pg_temp.h(2)],
    'repeat sign-up replaces the pending password'
);

-- Resend: cooldown, then ok, then hourly limit
DO $$
DECLARE s text; w integer;
BEGIN
    CALL auth.pr_resend_otp(pg_temp.v('c2')::uuid, pg_temp.otp(103), s, w);
    INSERT INTO r VALUES ('resend_now', s);
END $$;
SELECT is(pg_temp.v('resend_now'), 'rate_limited', 'resend before 30 s is rejected');
UPDATE auth.otp_challenge SET last_sent_at = now() - interval '31 seconds', created_at = now() - interval '31 seconds';
DO $$
DECLARE s text; w integer;
BEGIN
    CALL auth.pr_resend_otp(pg_temp.v('c2')::uuid, pg_temp.otp(104), s, w);
    INSERT INTO r VALUES ('resend_ok', s);
END $$;
SELECT is(pg_temp.v('resend_ok'), 'ok', 'resend after 30 s works');
SELECT is(
    (
        SELECT send_count::int FROM auth.otp_challenge
        WHERE id = pg_temp.v('c2')::uuid
    ), 2, 'send_count incremented'
);
UPDATE
    auth.otp_challenge SET
    last_sent_at = now() - interval '31 seconds', created_at = now() - interval '31 seconds',
    send_count = 5
WHERE id = pg_temp.v('c2')::uuid;
DO $$
DECLARE s text; w integer;
BEGIN
    CALL auth.pr_resend_otp(pg_temp.v('c2')::uuid, pg_temp.otp(105), s, w);
    INSERT INTO r VALUES ('resend_6th', s);
END $$;
SELECT is(pg_temp.v('resend_6th'), 'rate_limited', '6th send within an hour is rejected');
UPDATE auth.otp_challenge SET send_count = 1
WHERE id = pg_temp.v('c2')::uuid;

-- Verify: 3 wrong codes kill the challenge, and the attempts survive (returned, not raised)
DO $$
DECLARE u uuid; s text; a integer; p text;
BEGIN
    FOR i IN 1..4 LOOP
        CALL auth.pr_verify_otp(pg_temp.v('c2')::uuid, FALSE, u, s, a, p);
        INSERT INTO r VALUES ('wrong' || i, s || ':' || coalesce(a::text, '-'));
    END LOOP;
    CALL auth.pr_verify_otp(pg_temp.v('c2')::uuid, TRUE, u, s, a, p);
    INSERT INTO r VALUES ('right_after_dead', s);
END $$;
SELECT is(
    ARRAY[pg_temp.v('wrong1'), pg_temp.v('wrong2'), pg_temp.v('wrong3'), pg_temp.v('wrong4')],
    ARRAY['invalid:2', 'invalid:1', 'dead:0', 'dead:0'],
    'wrong codes count down 2, 1, then the challenge is dead'
);
SELECT is(pg_temp.v('right_after_dead'), 'dead', 'the right code no longer works on a dead challenge');

-- New challenge, correct code: activates the account; reuse fails
UPDATE auth.otp_challenge SET last_sent_at = now() - interval '2 hours', created_at = now() - interval '2 hours';
DO $$
DECLARE c uuid; s text; w integer; u uuid; a integer; p text;
BEGIN
    CALL auth.pr_create_otp_challenge(pg_temp.e('e1'), 'email_verification', pg_temp.otp(106), c, s, w);
    INSERT INTO r VALUES ('c3', c);
    CALL auth.pr_verify_otp(c, TRUE, u, s, a, p);
    INSERT INTO r VALUES ('verify_ok', s), ('verify_user', u), ('verify_purpose', p);
    CALL auth.pr_verify_otp(c, TRUE, u, s, a, p);
    INSERT INTO r VALUES ('verify_reuse', s);
END $$;
SELECT is(pg_temp.v('verify_ok'), 'ok', 'correct code accepted');
SELECT is(pg_temp.v('verify_user'), pg_temp.v('u1'), 'verification returns the account');
SELECT is(pg_temp.v('verify_purpose'), 'email_verification', 'verification returns the purpose');
SELECT results_eq(
    format('SELECT status::text, email_verified_at IS NOT NULL FROM auth.user_account WHERE id = %L', pg_temp.v('u1')),
    $$VALUES ('active', TRUE)$$,
    'email verification activates the account'
);
SELECT is(pg_temp.v('verify_reuse'), 'consumed', 'a used code cannot be reused');

-- Expired challenge
UPDATE auth.otp_challenge SET last_sent_at = now() - interval '2 hours', created_at = now() - interval '2 hours';
DO $$
DECLARE c uuid; s text; w integer; u uuid; a integer; p text;
BEGIN
    CALL auth.pr_create_otp_challenge(pg_temp.e('e1'), 'password_reset', pg_temp.otp(107), c, s, w);
    UPDATE auth.otp_challenge SET created_at = now() - interval '6 minutes', expires_at = now() - interval '1 minute' WHERE id = c;
    CALL auth.pr_verify_otp(c, TRUE, u, s, a, p);
    INSERT INTO r VALUES ('expired', s);
    CALL auth.pr_verify_otp(uuidv7(), TRUE, u, s, a, p);
    INSERT INTO r VALUES ('unknown_challenge', s);
END $$;
SELECT is(pg_temp.v('expired'), 'expired', 'an expired code is rejected (OTP_EXPIRED)');
SELECT is(pg_temp.v('unknown_challenge'), 'not_found', 'an unknown challenge id is not_found');

-- Other sign-up outcomes
DO $$
DECLARE u uuid; c uuid; s text; w integer;
BEGIN
    CALL auth.pr_create_account(pg_temp.e('e1'), pg_temp.h(3), pg_temp.i('f1'), pg_temp.otp(108), u, c, s, w);
    INSERT INTO r VALUES ('signup_active', s), ('signup_active_user', coalesce(u::text, 'null'));
    CALL auth.pr_create_otp_challenge(pg_temp.e('e9'), 'password_reset', pg_temp.otp(109), c, s, w);
    INSERT INTO r VALUES ('reset_unknown', s);
    CALL auth.pr_create_otp_challenge(pg_temp.e('e1'), 'email_verification', pg_temp.otp(110), c, s, w);
    INSERT INTO r VALUES ('verify_active', s);
END $$;
SELECT is(pg_temp.v('signup_active'), 'email_registered', 'sign-up with a registered email -> email_registered');
SELECT is(pg_temp.v('signup_active_user'), 'null', 'no account id is revealed for a registered email');
SELECT is(pg_temp.v('reset_unknown'), 'no_account', 'password reset for an unknown email -> no_account (API stays generic)');
SELECT is(pg_temp.v('verify_active'), 'already_verified', 'no verification code for an active account');

-- ===== Lockout =====
DO $$
DECLARE s text; t timestamptz;
BEGIN
    FOR i IN 1..5 LOOP
        CALL auth.pr_record_login_attempt(pg_temp.e('e1'), inet '10.0.0.1', FALSE, s, t);
        INSERT INTO r VALUES ('fail' || i, s);
    END LOOP;
    INSERT INTO r VALUES ('lock5', t);
END $$;
SELECT is(
    ARRAY[pg_temp.v('fail1'), pg_temp.v('fail4'), pg_temp.v('fail5')], ARRAY['failed', 'failed', 'locked'],
    '5 failures within 15 minutes lock the account'
);
SELECT is(pg_temp.v('lock5')::timestamptz, now() + interval '1 minute', 'first lockout lasts 1 minute');
SELECT is(
    (
        SELECT count(*)::int FROM audit.security_event
        WHERE event_type = 'lockout' AND user_id = pg_temp.v('u1')::uuid
    ), 1,
    'lockout logs a security event'
);
SELECT is(auth.fn_login_failures_recent(pg_temp.e('e1')), 5, 'fn_login_failures_recent counts the window');
UPDATE auth.user_account SET failed_login_count = 9
WHERE id = pg_temp.v('u1')::uuid;
DO $$
DECLARE s text; t timestamptz;
BEGIN
    CALL auth.pr_record_login_attempt(pg_temp.e('e1'), inet '10.0.0.1', FALSE, s, t);
    INSERT INTO r VALUES ('lock10', t);
    UPDATE auth.user_account SET failed_login_count = 19 WHERE id = pg_temp.v('u1')::uuid;
    CALL auth.pr_record_login_attempt(pg_temp.e('e1'), inet '10.0.0.1', FALSE, s, t);
    INSERT INTO r VALUES ('lock20', t);
END $$;
SELECT is(pg_temp.v('lock10')::timestamptz, now() + interval '5 minutes', '10th consecutive failure: 5 minutes');
SELECT is(pg_temp.v('lock20')::timestamptz, now() + interval '60 minutes', '20th consecutive failure: 60 minutes');
DO $$
DECLARE s text; t timestamptz;
BEGIN
    CALL auth.pr_record_login_attempt(pg_temp.e('e9'), NULL, FALSE, s, t);
    INSERT INTO r VALUES ('unknown_email', s);
    UPDATE auth.login_attempt SET attempted_at = now() - interval '1 second';
    CALL auth.pr_record_login_attempt(pg_temp.e('e1'), NULL, TRUE, s, t);
    INSERT INTO r VALUES ('success', s);
END $$;
SELECT is(pg_temp.v('unknown_email'), 'failed', 'unknown email looks like any failure');
SELECT results_eq(
    format('SELECT failed_login_count::int, locked_until, last_login_at FROM auth.user_account WHERE id = %L', pg_temp.v('u1')),
    $$VALUES (0, NULL::timestamptz, now())$$,
    'success resets the counters and records last_login_at'
);
SELECT is(auth.fn_login_failures_recent(pg_temp.e('e1')), 0, 'failures before the last success no longer count');

-- Unknown emails lock out exactly like accounts (S16, doc 07 T26: no enumeration via lockout).
DO $$
DECLARE s text; t timestamptz;
BEGIN
    FOR i IN 1..5 LOOP
        CALL auth.pr_record_login_attempt(pg_temp.e('ghost'), inet '10.0.0.9', FALSE, s, t);
        INSERT INTO r VALUES ('ghost' || i, s);
    END LOOP;
    INSERT INTO r VALUES ('ghost_lock', t);
END $$;
SELECT is(
    ARRAY[pg_temp.v('ghost1'), pg_temp.v('ghost4'), pg_temp.v('ghost5')], ARRAY['failed', 'failed', 'locked'],
    'an unknown email is locked after the same 5 failures as an account'
);
SELECT is(pg_temp.v('ghost_lock')::timestamptz, now() + interval '1 minute', 'unknown email: first lock 1 minute');
SELECT is(
    auth.fn_unknown_email_locked_until(pg_temp.e('ghost')), now() + interval '1 minute',
    'the API pre-check sees the same lock'
);
SELECT is(
    auth.fn_unknown_email_locked_until(pg_temp.e('e1')), NULL,
    'an existing account never gets the derived lock (its own locked_until applies)'
);
SELECT is(
    (SELECT count(*)::int FROM audit.security_event WHERE event_type = 'lockout' AND user_id IS NULL), 0,
    'no security event for an email without an account'
);

-- ===== Refresh tokens =====
SELECT throws_ok(
    format(
        'CALL auth.pr_issue_refresh_token(%L, %L, %L, NULL, NULL, NULL)',
        pg_temp.v('u1'), pg_temp.b('a1'), pg_temp.i('f1')
    ),
    '42501', NULL, 'issuing a token without the actor set fails'
);
SELECT set_config('app.user_id', pg_temp.v('u1'), TRUE);
DO $$
DECLARE t uuid; f uuid; e timestamptz; u uuid; t2 uuid; role text; s text;
BEGIN
    CALL auth.pr_issue_refresh_token(pg_temp.v('u1')::uuid, pg_temp.b('a1'), pg_temp.i('f1'), t, f, e);
    INSERT INTO r VALUES ('family', f), ('exp', e);
    u := NULL; f := NULL;
    CALL auth.pr_rotate_refresh_token(pg_temp.b('a1'), pg_temp.b('a2'), pg_temp.i('f1'), u, f, t2, e, role, s);
    INSERT INTO r VALUES ('rotate1', s), ('rotate1_family', f), ('rotate1_role', role);
    CALL auth.pr_rotate_refresh_token(pg_temp.b('a2'), pg_temp.b('a3'), pg_temp.i('f1'), u, f, t2, e, role, s);
    INSERT INTO r VALUES ('rotate2', s);
    CALL auth.pr_rotate_refresh_token(pg_temp.b('a1'), pg_temp.b('a4'), pg_temp.i('f1'), u, f, t2, e, role, s);
    INSERT INTO r VALUES ('reuse', s);
    CALL auth.pr_rotate_refresh_token(pg_temp.b('a3'), pg_temp.b('a5'), pg_temp.i('f1'), u, f, t2, e, role, s);
    INSERT INTO r VALUES ('after_reuse', s);
    CALL auth.pr_rotate_refresh_token(pg_temp.b('99'), pg_temp.b('a6'), pg_temp.i('f1'), u, f, t2, e, role, s);
    INSERT INTO r VALUES ('unknown_token', s);
END $$;
SELECT is(pg_temp.v('exp')::timestamptz, now() + interval '60 days', 'refresh tokens live 60 days');
SELECT is(pg_temp.v('rotate1'), 'ok', 'rotation returns a new token');
SELECT is(pg_temp.v('rotate1_family'), pg_temp.v('family'), 'rotation stays in the family');
SELECT is(pg_temp.v('rotate1_role'), 'user', 'rotation returns the role for the new access token');
SELECT is(pg_temp.v('rotate2'), 'ok', 'the child token rotates too');
SELECT is(pg_temp.v('reuse'), 'reuse_detected', 'presenting a used token is detected as reuse');
SELECT is(
    (
        SELECT count(*)::int FROM auth.refresh_token
        WHERE family_id = pg_temp.v('family')::uuid AND revoked_at IS NULL
    ), 0,
    'reuse revokes the whole family'
);
SELECT is(pg_temp.v('after_reuse'), 'reuse_detected', 'even the newest token of the family is dead after reuse');
SELECT is(
    (
        SELECT count(*)::int FROM audit.security_event
        WHERE event_type = 'refresh_reuse' AND user_id = pg_temp.v('u1')::uuid
    ), 2,
    'each reuse logs a refresh_reuse security event'
);
SELECT is(pg_temp.v('unknown_token'), 'invalid', 'unknown token -> invalid');

DO $$
DECLARE t uuid; f uuid; e timestamptz; u uuid; t2 uuid; role text; s text;
BEGIN
    CALL auth.pr_issue_refresh_token(pg_temp.v('u1')::uuid, pg_temp.b('b1'), pg_temp.i('f1'), t, f, e);
    CALL auth.pr_rotate_refresh_token(pg_temp.b('b1'), pg_temp.b('b2'), pg_temp.i('f9'), u, f, t2, e, role, s);
    INSERT INTO r VALUES ('other_installation', s);
END $$;
SELECT is(pg_temp.v('other_installation'), 'reuse_detected', 'a token presented from another installation is treated as stolen');

-- Revocation scopes
DO $$
DECLARE t uuid; f1 uuid; f2 uuid; f3 uuid; e timestamptz; n integer;
BEGIN
    CALL auth.pr_issue_refresh_token(pg_temp.v('u1')::uuid, pg_temp.b('c1'), pg_temp.i('f1'), t, f1, e);
    CALL auth.pr_issue_refresh_token(pg_temp.v('u1')::uuid, pg_temp.b('c2'), pg_temp.i('f2'), t, f2, e);
    CALL auth.pr_issue_refresh_token(pg_temp.v('u1')::uuid, pg_temp.b('c3'), pg_temp.i('f3'), t, f3, e);
    CALL auth.pr_revoke_tokens(pg_temp.v('u1')::uuid, 'family', 'logout', f1, NULL, n);
    INSERT INTO r VALUES ('revoke_family', n);
    CALL auth.pr_revoke_tokens(pg_temp.v('u1')::uuid, 'all', 'logout_all', NULL, f3, n);
    INSERT INTO r VALUES ('revoke_all_keep', n), ('kept_family', f3);
END $$;
SELECT is(pg_temp.v('revoke_family'), '1', 'logout revokes one family');
SELECT is(pg_temp.v('revoke_all_keep'), '1', 'logout-all revokes the rest, keeping the requested family');
SELECT is(
    (
        SELECT count(*)::int FROM auth.refresh_token
        WHERE user_id = pg_temp.v('u1')::uuid AND revoked_at IS NULL
    ),
    1, 'only the kept session remains'
);

-- ===== Passwords =====
DO $$
BEGIN
    FOR i IN 10..15 LOOP
        CALL auth.pr_set_password(pg_temp.v('u1')::uuid, pg_temp.h(i), NULL);
    END LOOP;
END $$;
SELECT is(
    (SELECT array_agg(x::text) FROM auth.fn_password_history(pg_temp.v('u1')::uuid) AS x),
    ARRAY[pg_temp.h(15), pg_temp.h(14), pg_temp.h(13), pg_temp.h(12), pg_temp.h(11)],
    'password history keeps the newest 5'
);
SELECT is(
    (
        SELECT count(*)::int FROM auth.password_history
        WHERE user_id = pg_temp.v('u1')::uuid
    ), 5, 'older hashes are deleted'
);
SELECT is(
    (
        SELECT count(*)::int FROM auth.refresh_token
        WHERE user_id = pg_temp.v('u1')::uuid AND revoked_at IS NULL
    ), 0,
    'a password reset revokes every session'
);

-- ===== Social sign-in =====
SELECT set_config('app.user_id', '', TRUE);
DO $$
DECLARE u uuid; s text;
BEGIN
    CALL auth.pr_create_oauth_account('google', 'sub-5a', pg_temp.e('e2'), NULL, u, s);
    INSERT INTO r VALUES ('oauth_new', s), ('oauth_user', u);
    CALL auth.pr_create_oauth_account('google', 'sub-5a', pg_temp.e('e2'), NULL, u, s);
    INSERT INTO r VALUES ('oauth_again', s);
    CALL auth.pr_create_oauth_account('apple', 'sub-5b', pg_temp.e('e1'), NULL, u, s);
    INSERT INTO r VALUES ('oauth_existing_email', s);
END $$;
SELECT is(pg_temp.v('oauth_new'), 'created', 'first social sign-in creates an active account');
SELECT is(
    (SELECT status::text FROM auth.fn_find_identity('google', 'sub-5a')), 'active', 'the identity is findable'
);
SELECT is(pg_temp.v('oauth_again'), 'existing', 'second social sign-in finds the account');
SELECT is(pg_temp.v('oauth_existing_email'), 'link_required', 'never links silently to an existing email account');
SELECT set_config('app.user_id', pg_temp.v('u1'), TRUE);
SELECT throws_ok(
    format('CALL auth.pr_link_identity(%L, %L, %L)', pg_temp.v('u1'), 'google', 'sub-5a'),
    'P0001', NULL, 'linking an identity owned by another account -> IDENTITY_ALREADY_LINKED'
);
SELECT lives_ok(
    format('CALL auth.pr_link_identity(%L, %L, %L)', pg_temp.v('u1'), 'apple', 'sub-5b'),
    'linking a free identity to the actor works'
);
SELECT throws_ok(
    format('CALL auth.pr_link_identity(%L, %L, %L)', pg_temp.v('oauth_user'), 'apple', 'sub-5c'),
    '42501', NULL, 'cannot link an identity to someone else''s account'
);

-- Lookups
SELECT is(
    (SELECT user_id FROM auth.fn_find_account_by_email(pg_temp.e('e1'))), pg_temp.v('u1')::uuid,
    'account lookup by email'
);
SELECT is(
    (SELECT count(*)::int FROM auth.fn_find_account_by_email(pg_temp.e('77'))), 0, 'unknown email -> no row'
);
SELECT is(
    (SELECT is_usable FROM auth.fn_refresh_token_lookup(pg_temp.b('a1'))), FALSE, 'a revoked token is not usable'
);
SELECT is(
    (SELECT attempts_left FROM auth.fn_get_otp_challenge(pg_temp.v('c2')::uuid)), 0, 'challenge state lookup'
);

SELECT * FROM finish();
ROLLBACK;
