-- Partition maintenance, retention and auth purge (doc 05 sections 9 and 11).
BEGIN;
SELECT no_plan();
-- Bound display depends on the session TimeZone; show UTC so the expected text is stable.
SET LOCAL timezone = 'UTC';

-- ===== ops.pr_ensure_partitions with a mocked date =====
CREATE TEMP TABLE r (k text PRIMARY KEY, v integer);
DO $$
DECLARE c integer; a integer;
BEGIN
    CALL ops.pr_ensure_partitions('2030-01-15', c, a);
    INSERT INTO r VALUES ('created', c), ('alerts', a);
    CALL ops.pr_ensure_partitions('2030-01-15', c, a);
    INSERT INTO r VALUES ('created_again', c);
END $$;
SELECT is(
    (
        SELECT v FROM r
        WHERE k = 'created'
    ), 44, '11 partitioned tables x 4 months (2030-01..2030-04) created'
);
SELECT is((
    SELECT v FROM r
    WHERE k = 'alerts'
), 0, 'no alerts while DEFAULT partitions are empty');
SELECT is((
    SELECT v FROM r
    WHERE k = 'created_again'
), 0, 'second run is a no-op (idempotent)');
SELECT has_table('nutrition', 'meal_p2030_04', 'nutrition.meal_p2030_04 exists');
SELECT
    is(
        pg_get_expr(c.relpartbound, c.oid),
        $$FOR VALUES FROM ('2030-01-01 00:00:00+00') TO ('2030-02-01 00:00:00+00')$$,
        'timestamptz partitions have explicit UTC bounds'
    )
FROM pg_class AS c
WHERE c.oid = 'hydration.intake_p2030_01'::regclass;
SELECT
    is(
        pg_get_expr(c.relpartbound, c.oid),
        $$FOR VALUES FROM ('2030-01-01') TO ('2030-02-01')$$,
        'date partitions have date bounds'
    )
FROM pg_class AS c
WHERE c.oid = 'nutrition.daily_summary_p2030_01'::regclass;
SELECT ok(
    EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgrelid = 'nutrition.meal_p2030_04'::regclass AND tgname = 'trg_set_updated_at'
    ),
    'new partitions inherit the parent''s row triggers'
);

-- DEFAULT partition with rows -> alert (warning + ops_alert security event), run continues
INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000000e1', 'ue1@example.test', 'active');
INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
VALUES (
    uuidv7(), timestamptz '2035-06-10 08:00:00+00', '0192f000-0000-7000-8000-0000000000e1', '2035-06-10',
    'water', 250, 1, 250, 'manual'
);
SELECT is(
    (SELECT count(*)::int FROM hydration.intake_default), 1, 'a row with no matching month lands in DEFAULT'
);
DO $$
DECLARE c integer; a integer;
BEGIN
    CALL ops.pr_ensure_partitions('2035-06-01', c, a);
    INSERT INTO r VALUES ('alert_created', c), ('alert_alerts', a);
END $$;
SELECT ok((
    SELECT v FROM r
    WHERE k = 'alert_alerts'
) >= 2, 'non-empty DEFAULT raises alerts (table + blocked month)');
SELECT is(
    (
        SELECT count(*)::int FROM audit.security_event
        WHERE event_type = 'ops_alert' AND details ->> 'table' = 'hydration.intake'
    ),
    1, 'ops_alert security event names the table'
);
SELECT is(
    to_regclass('hydration.intake_p2035_06'), NULL::regclass,
    'the month already present in DEFAULT is skipped, not forced'
);
SELECT isnt(to_regclass('hydration.intake_p2035_07'), NULL::regclass, 'other months are still created');
SELECT isnt(to_regclass('nutrition.meal_p2035_06'), NULL::regclass, 'other tables are unaffected');

-- ===== ops.pr_apply_retention =====
-- notify.notification keeps 3 months, audit.security_event 12, audit.change_log 36; health logs forever.
DO $$
DECLARE d integer;
BEGIN
    CALL ops.pr_apply_retention('2030-05-10', d);
    INSERT INTO r VALUES ('dropped', d);
END $$;
SELECT is(to_regclass('notify.notification_p2030_01'), NULL::regclass, 'notification partition older than 3 months dropped');
SELECT isnt(to_regclass('notify.notification_p2030_02'), NULL::regclass, 'notification partition inside the window kept');
SELECT isnt(to_regclass('nutrition.meal_p2030_01'), NULL::regclass, 'health logs (no retention) never dropped');
SELECT isnt(to_regclass('audit.change_log_p2030_01'), NULL::regclass, 'audit change log kept 36 months');
SELECT isnt(to_regclass('notify.notification_default'), NULL::regclass, 'DEFAULT partitions are never dropped');
SELECT ok((
    SELECT v FROM r
    WHERE k = 'dropped'
) >= 1, 'retention reports dropped partitions');

-- ===== ops.pr_purge_auth_artifacts =====
INSERT INTO auth.login_attempt (email, success, attempted_at) VALUES
('ue1@example.test', FALSE, now() - interval '91 days'),
('ue1@example.test', FALSE, now() - interval '89 days');
INSERT INTO auth.otp_challenge (user_id, email, purpose, code, expires_at, created_at, last_sent_at) VALUES
(
    '0192f000-0000-7000-8000-0000000000e1', 'ue1@example.test', 'password_reset',
    '123456', now() - interval '8 days' + interval '5 minutes',
    now() - interval '8 days', now() - interval '8 days'
),
(
    '0192f000-0000-7000-8000-0000000000e1', 'ue1@example.test', 'password_reset',
    '123456', now() + interval '5 minutes', now(), now()
);
INSERT INTO auth.refresh_token (user_id, family_id, token_hash, issued_at, expires_at, revoked_at, revoked_reason) VALUES
(
    '0192f000-0000-7000-8000-0000000000e1', uuidv7(), decode(repeat('71', 32), 'hex'),
    now() - interval '100 days', now() - interval '40 days', NULL, NULL
),
(
    '0192f000-0000-7000-8000-0000000000e1', uuidv7(), decode(repeat('72', 32), 'hex'),
    now() - interval '50 days', now() + interval '10 days', now() - interval '31 days', 'logout'
),
(
    '0192f000-0000-7000-8000-0000000000e1', uuidv7(), decode(repeat('73', 32), 'hex'),
    now() - interval '1 day', now() + interval '59 days', NULL, NULL
);
DO $$
DECLARE d integer;
BEGIN
    CALL ops.pr_purge_auth_artifacts(NULL, 10000, d);
    INSERT INTO r VALUES ('purged', d);
    CALL ops.pr_purge_auth_artifacts(NULL, 10000, d);
    INSERT INTO r VALUES ('purged_again', d);
END $$;
SELECT is((
    SELECT v FROM r
    WHERE k = 'purged'
), 4, 'purged 1 login attempt, 1 OTP challenge, 2 refresh tokens');
SELECT is((
    SELECT v FROM r
    WHERE k = 'purged_again'
), 0, 'nothing left to purge on the second run');
SELECT results_eq(
    $$SELECT
        (SELECT count(*)::int FROM auth.login_attempt WHERE email = 'ue1@example.test'),
        (SELECT count(*)::int FROM auth.otp_challenge WHERE user_id = '0192f000-0000-7000-8000-0000000000e1'),
        (SELECT count(*)::int FROM auth.refresh_token WHERE user_id = '0192f000-0000-7000-8000-0000000000e1')$$,
    $$VALUES (1, 1, 1)$$,
    'recent artifacts are kept'
);
SELECT throws_ok(
    'CALL ops.pr_purge_auth_artifacts(NULL, 0, NULL)', '22023', NULL, 'batch size must be positive'
);

SELECT * FROM finish();
ROLLBACK;
