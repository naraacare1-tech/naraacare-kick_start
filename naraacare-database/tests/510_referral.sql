-- Referrals (Session 11; doc 06 section 6, OQ-39): attribution rules (self, unknown code, account
-- older than 7 days, repeat, installation already seen), the nightly tally (qualified at 30 active
-- days within 60 days of sign-up with email verified and onboarding done; disqualified after 60),
-- one reward per referrer at 5 qualified friends: 30 days, or 50 for a STAR referrer, starting after
-- a paid period.
BEGIN;
SELECT no_plan();

CREATE FUNCTION pg_temp.u(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(20736 + n), 12, '0'))::uuid
$$;
CREATE FUNCTION pg_temp.account(n integer, p_installation uuid DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO auth.user_account (id, email, status, email_verified_at, installation_id)
    VALUES (pg_temp.u(n), 'r' || n || '@example.test', 'active', now(), p_installation);
    INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at)
    VALUES (pg_temp.u(n), 6, now());
    RETURN pg_temp.u(n);
END
$$;
CREATE FUNCTION pg_temp.code(p_user uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE c text;
BEGIN
    PERFORM set_config('app.user_id', p_user::text, TRUE);
    CALL billing.pr_ensure_referral_code(p_user, c);
    RETURN c;
END
$$;
CREATE FUNCTION pg_temp.attribute(p_user uuid, p_code text, p_installation uuid DEFAULT NULL) RETURNS text
LANGUAGE plpgsql AS $$
DECLARE s text;
BEGIN
    PERFORM set_config('app.user_id', p_user::text, TRUE);
    CALL billing.pr_attribute_referral(p_user, p_code, p_installation, s);
    RETURN s;
END
$$;
-- A referred friend who signed up p_days_ago days ago and was active on p_active distinct days.
CREATE FUNCTION pg_temp.friend(n integer, p_code text, p_active integer, p_days_ago integer DEFAULT 45)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE f uuid := pg_temp.account(n);
BEGIN
    PERFORM pg_temp.attribute(f, p_code);
    UPDATE auth.user_account SET created_at = now() - p_days_ago * interval '1 day' WHERE id = f;
    INSERT INTO app.user_activity_day (user_id, local_date, has_hydration)
    SELECT f, (now() - p_days_ago * interval '1 day')::date + i, TRUE FROM generate_series(0, p_active - 1) AS i;
    RETURN f;
END
$$;
CREATE FUNCTION pg_temp.tally() RETURNS text LANGUAGE plpgsql AS $$
DECLARE q integer; r integer;
BEGIN
    CALL ops.pr_tally_referrals(NULL, q, r);
    RETURN q || '/' || r;
END
$$;

-- ===== Codes and attribution =====
SELECT pg_temp.account(1);
SELECT matches(pg_temp.code(pg_temp.u(1)), '^[A-HJ-NP-Z2-9]{8}$', 'an 8-character code without look-alike characters');
SELECT is(pg_temp.code(pg_temp.u(1)), pg_temp.code(pg_temp.u(1)), 'the code is created once');
CREATE TEMP TABLE c AS SELECT pg_temp.code(pg_temp.u(1)) AS code;

SELECT is(pg_temp.attribute(pg_temp.u(1), (SELECT code FROM c)), 'ignored_self', 'self-referral is ignored');
SELECT pg_temp.account(2);
SELECT is(pg_temp.attribute(pg_temp.u(2), 'ZZZZZZZZ'), 'ignored_unknown_code', 'an unknown code is ignored');
SELECT is(pg_temp.attribute(pg_temp.u(2), (SELECT code FROM c)), 'attributed', 'a new friend is attributed (the API upper-cases codes)');
SELECT is(pg_temp.attribute(pg_temp.u(2), (SELECT code FROM c)), 'ignored_already_attributed', 'only once');
SELECT pg_temp.account(3, '0192f000-0000-7000-8000-00000000d3d3');
SELECT pg_temp.account(4);
SELECT is(pg_temp.attribute(pg_temp.u(4), (SELECT code FROM c), '0192f000-0000-7000-8000-00000000d3d3'),
    'ignored_device_seen', 'an installation already used by another account is ignored');
UPDATE auth.user_account SET created_at = now() - interval '8 days' WHERE id = pg_temp.u(4);
SELECT is(pg_temp.attribute(pg_temp.u(4), (SELECT code FROM c)), 'ignored_too_old', 'accounts older than 7 days are ignored');
SELECT throws_ok($$SELECT pg_temp.attribute(pg_temp.u(4), 'bad code!')$$, '23514', NULL, 'a malformed code is refused by its domain');
DELETE FROM billing.referral WHERE referred_user_id = pg_temp.u(2);  -- keep the tally fixture below exact

-- ===== Tally and reward (referrer 1 is STANDARD) =====
SELECT pg_temp.friend(10, (SELECT code FROM c), 29);
SELECT pg_temp.friend(11, (SELECT code FROM c), 30);
SELECT pg_temp.friend(12, (SELECT code FROM c), 31);
SELECT pg_temp.friend(13, (SELECT code FROM c), 30);
SELECT pg_temp.friend(14, (SELECT code FROM c), 30);
SELECT pg_temp.friend(15, (SELECT code FROM c), 10, 61);  -- the 60-day window has passed
SELECT is(pg_temp.tally(), '4/0', '30 and 31 active days qualify, 29 does not; 4 qualified is not yet a reward');
SELECT is(
    (SELECT status || ':' || coalesce(disqualify_reason, '') FROM billing.referral WHERE referred_user_id = pg_temp.u(15)),
    'disqualified:window_passed', 'a friend who did not make it within 60 days is disqualified'
);
SELECT is((SELECT status FROM billing.referral WHERE referred_user_id = pg_temp.u(10)), 'pending', '29 days stays pending');
INSERT INTO app.user_activity_day (user_id, local_date, has_sleep)
VALUES (pg_temp.u(10), (now() - interval '45 days')::date + 40, TRUE);
SELECT is(pg_temp.tally(), '1/1', 'the 5th qualified friend triggers the reward');
SELECT is((SELECT reward_days FROM billing.referral_reward WHERE referrer_id = pg_temp.u(1)), 30::smallint,
    'a STANDARD referrer gets 30 days of STAR');
SELECT is(pg_temp.tally(), '0/0', 'the reward is given once');
SELECT is((SELECT count(*)::int FROM billing.entitlement_grant WHERE user_id = pg_temp.u(1)), 1, 'one grant');

-- ===== A paying STAR referrer: 50 days, starting after the paid period =====
SELECT pg_temp.account(20);
INSERT INTO billing.subscription (
    user_id, platform, product_id, purchase_token, status, auto_renew, current_period_start,
    current_period_end, environment, last_verified_at
) VALUES (
    pg_temp.u(20), 'google_play', 'star_monthly', 'tok-510-paid', 'active', TRUE, now() - interval '10 days',
    now() + interval '20 days', 'sandbox', now()
);
CREATE TEMP TABLE c2 AS SELECT pg_temp.code(pg_temp.u(20)) AS code;
SELECT pg_temp.friend(30 + i, (SELECT code FROM c2), 30) FROM generate_series(0, 4) AS i;
SELECT is(pg_temp.tally(), '5/1', 'five qualified friends: rewarded');
SELECT is((SELECT reward_days FROM billing.referral_reward WHERE referrer_id = pg_temp.u(20)), 50::smallint,
    'a STAR referrer gets 50 days');
SELECT is(
    (SELECT g.starts_at FROM billing.entitlement_grant AS g WHERE g.user_id = pg_temp.u(20)),
    (SELECT current_period_end FROM billing.subscription WHERE user_id = pg_temp.u(20)),
    'the grant starts when the paid period ends (no overlap with what they paid for)'
);

SELECT * FROM finish();
ROLLBACK;
