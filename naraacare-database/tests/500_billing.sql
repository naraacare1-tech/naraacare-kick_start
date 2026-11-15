-- Billing (Session 11; doc 04 sections 2.12 and 3, doc 06 section 9, doc 07 T10/T11): binding a
-- verified purchase to one account (receipt sharing refused and logged), entitlement transitions
-- (active -> canceled keeps access to the period end -> expired; grace; refund; grants), webhook
-- state updates, idempotent notifications and transactions, history ownership.
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-000000005001', 'b1@example.test', 'active'),
('0192f000-0000-7000-8000-000000005002', 'b2@example.test', 'active');

CREATE FUNCTION pg_temp.u(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-00000000500' || n)::uuid
$$;
CREATE FUNCTION pg_temp.bind(
    p_user uuid, p_token text, p_status text, p_end timestamptz, p_platform text DEFAULT 'google_play',
    p_original text DEFAULT NULL
) RETURNS text LANGUAGE plpgsql AS $$
DECLARE sid uuid; s text;
BEGIN
    PERFORM set_config('app.user_id', p_user::text, TRUE);
    CALL billing.pr_upsert_subscription(
        p_user, p_platform, 'star_monthly', p_token, p_original, p_status, p_status = 'active',
        p_end - interval '30 days', p_end, 'sandbox', sid, s
    );
    RETURN s;
END
$$;
CREATE FUNCTION pg_temp.tier(p_user uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE t text;
BEGIN
    PERFORM set_config('app.user_id', p_user::text, TRUE);
    SELECT tier_code || '/' || source INTO t FROM billing.fn_current_entitlement(p_user);
    RETURN t;
END
$$;
CREATE FUNCTION pg_temp.apply(p_token text, p_status text, p_end timestamptz) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE owner uuid;
BEGIN
    CALL billing.pr_apply_store_state(
        'google_play', p_token, NULL, 'star_monthly', p_status, FALSE,
        p_end - interval '30 days', p_end, 'sandbox', owner
    );
    RETURN owner;
END
$$;

-- ===== Default and binding =====
SELECT is(pg_temp.tier(pg_temp.u(1)), 'standard/default', 'no subscription or grant: STANDARD');
SELECT ok(pg_temp.bind(pg_temp.u(1), 'tok-500-a', 'active', now() + interval '30 days') <> 'token_in_use',
    'a verified purchase binds to the caller');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'star/store', 'an active store subscription gives STAR');
SELECT ok(pg_temp.bind(pg_temp.u(1), 'tok-500-a', 'active', now() + interval '30 days') <> 'token_in_use',
    'verifying again on the same account is idempotent');
SELECT is(
    (SELECT count(*)::int FROM billing.subscription WHERE purchase_token = 'tok-500-a'), 1,
    'still one subscription row'
);

-- ===== Receipt sharing (T11) =====
SELECT is(pg_temp.bind(pg_temp.u(2), 'tok-500-a', 'active', now() + interval '30 days'), 'token_in_use',
    'the same purchase on another account is refused');
SELECT is(pg_temp.tier(pg_temp.u(2)), 'standard/default', 'the other account stays STANDARD');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'star/store', 'the owner keeps STAR');
SELECT is(
    (SELECT count(*)::int FROM audit.security_event
     WHERE event_type = 'purchase_token_reuse' AND user_id = pg_temp.u(2)), 1,
    'receipt sharing is logged as a security event'
);
SELECT is(pg_temp.bind(pg_temp.u(2), NULL, 'active', now() + interval '30 days', 'app_store', '2000000000500001'),
    'created', 'an App Store purchase binds by original transaction id');
SELECT is(pg_temp.bind(pg_temp.u(1), NULL, 'active', now() + interval '30 days', 'app_store', '2000000000500001'),
    'token_in_use', 'the same original transaction on another account is refused');

-- ===== Transitions (webhook / reconcile state, whoever owns the key) =====
SELECT is(pg_temp.apply('tok-500-a', 'canceled', now() + interval '10 days'), pg_temp.u(1),
    'state updates find the owner');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'star/store', 'canceled (auto-renew off) keeps STAR until the period end');
SELECT pg_temp.apply('tok-500-a', 'canceled', now() - interval '1 minute');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'standard/default', 'canceled past the period end: STANDARD');
SELECT pg_temp.apply('tok-500-a', 'in_grace', now() - interval '1 day');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'star/store', 'billing grace keeps STAR');
SELECT pg_temp.apply('tok-500-a', 'expired', now() - interval '1 day');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'standard/default', 'expired: STANDARD');
SELECT pg_temp.apply('tok-500-a', 'active', now() + interval '30 days');
SELECT pg_temp.apply('tok-500-a', 'refunded', now() + interval '30 days');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'standard/default', 'a refund ends STAR at once, even inside the period');
SELECT is(pg_temp.apply('tok-unknown', 'active', now() + interval '30 days'), NULL::uuid,
    'a notification for an unknown purchase binds to nobody');

-- ===== Grants =====
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES (pg_temp.u(1), 'star', 'promo', now() + interval '1 day', now() + interval '31 days');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'standard/default', 'a grant that has not started yet gives nothing');
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES (pg_temp.u(1), 'star', 'promo', now() - interval '1 day', now() + interval '5 days');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'star/promo', 'an active grant gives STAR');
SELECT pg_temp.apply('tok-500-a', 'active', now() + interval '30 days');
SELECT is(pg_temp.tier(pg_temp.u(1)), 'star/store', 'a store subscription is reported before a grant');

-- ===== Notifications and transactions are idempotent =====
DO $$
DECLARE s1 text; s2 text;
BEGIN
    CALL billing.pr_record_store_notification('google_play', 'msg-500-1', 'subscription_notification', repeat('a', 64), s1);
    CALL billing.pr_record_store_notification('google_play', 'msg-500-1', 'subscription_notification', repeat('a', 64), s2);
    CREATE TEMP TABLE notes AS SELECT s1, s2;
END $$;
SELECT is((SELECT s2 FROM notes), 'duplicate', 'a replayed notification is reported as duplicate');
SELECT isnt((SELECT s1 FROM notes), 'duplicate', 'the first delivery is processed');
CALL billing.pr_record_transaction('google_play', 'tok-500-a', NULL, 'GPA.500-1', 'purchase', 199000000, 'INR', now());
CALL billing.pr_record_transaction('google_play', 'tok-500-a', NULL, 'GPA.500-1', 'purchase', 199000000, 'INR', now());
SELECT is((SELECT count(*)::int FROM billing.store_transaction WHERE store_transaction_id = 'GPA.500-1'), 1,
    'a transaction is recorded once');

-- ===== Ownership =====
SELECT set_config('app.user_id', pg_temp.u(2)::text, TRUE);
SELECT throws_ok(
    format('SELECT * FROM billing.fn_billing_history(%L, NULL, 10)', pg_temp.u(1)),
    '42501', NULL, 'nobody reads another user''s billing history'
);
SELECT throws_ok(
    format('SELECT * FROM billing.fn_current_entitlement(%L)', pg_temp.u(1)),
    '42501', NULL, 'nobody reads another user''s entitlement'
);

SELECT * FROM finish();
ROLLBACK;
