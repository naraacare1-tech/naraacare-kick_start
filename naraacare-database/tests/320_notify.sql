-- Devices, notification preferences, reminder schedules and the worker reminder fan-out
-- (Session 09; doc 04 section 2.7, OQ-41).
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000003e1', 'ue1@example.test', 'active'),
('0192f000-0000-7000-8000-0000000003e2', 'ue2@example.test', 'active'),
('0192f000-0000-7000-8000-0000000003e3', 'ue3@example.test', 'pending_deletion');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at, timezone, wake_local, sleep_start_local) VALUES
('0192f000-0000-7000-8000-0000000003e1', 6, now(), 'Asia/Kolkata', '07:00', '23:00'),
('0192f000-0000-7000-8000-0000000003e2', 6, now(), 'Europe/London', '07:00', '23:00'),
('0192f000-0000-7000-8000-0000000003e3', 6, now(), 'Asia/Kolkata', '07:00', '23:00');

CREATE FUNCTION pg_temp.hash(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('00000000-0000-7000-8000-' || lpad(to_hex(n), 12, '0'))::uuid
$$;
CREATE FUNCTION pg_temp.token(n integer) RETURNS text LANGUAGE sql AS $$
    SELECT 'fcm-token:' || n
$$;
-- A moment at a local wall-clock time today in a timezone.
CREATE FUNCTION pg_temp.local(p_tz text, p_time time) RETURNS timestamptz LANGUAGE sql AS $$
    SELECT (common.fn_local_date(p_tz)::timestamp + p_time) AT TIME ZONE p_tz
$$;

-- ===== Devices =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000003e1', TRUE);
CREATE TEMP TABLE dev (n integer, id uuid);
DO $$
DECLARE v uuid;
BEGIN
    CALL notify.pr_register_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(1), 'android', pg_temp.token(1), '1.0.0+1', v);
    INSERT INTO dev VALUES (1, v);
    CALL notify.pr_register_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(1), 'android', pg_temp.token(2), '1.0.1+2', v);
    INSERT INTO dev VALUES (2, v);
END
$$;
SELECT is((SELECT count(DISTINCT id)::integer FROM dev), 1, 'registering the same installation again updates the device');
SELECT is(
    (SELECT row(app_version, push_token = pg_temp.token(2), revoked_at IS NULL)::text FROM notify.device WHERE id = (SELECT id FROM dev LIMIT 1)),
    '(1.0.1+2,t,t)', 'new token and app version stored'
);
SELECT throws_ok(
    $$CALL notify.pr_register_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(2), 'windows', pg_temp.token(3), '1.0.0', NULL)$$,
    '23514', NULL, 'an unknown platform is refused'
);
SELECT throws_ok(
    $$CALL notify.pr_register_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(2), 'ios', pg_temp.token(3), '1.0<script>', NULL)$$,
    '23514', NULL, 'an app version with markup is refused (domain)'
);
SELECT throws_ok(
    $$CALL notify.pr_register_device('0192f000-0000-7000-8000-0000000003e2', pg_temp.hash(9), 'ios', pg_temp.token(9), '1.0.0', NULL)$$,
    '42501', NULL, 'nobody can register a device for another user'
);
DO $$
DECLARE v uuid;
BEGIN
    FOR n IN 10..21 LOOP
        CALL notify.pr_register_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(n), 'ios', pg_temp.token(n), '1.0.0', v);
    END LOOP;
END
$$;
SELECT is(
    (SELECT count(*)::integer FROM notify.device WHERE user_id = '0192f000-0000-7000-8000-0000000003e1' AND revoked_at IS NULL),
    10, 'at most 10 active devices: the least recently seen are revoked'
);
SELECT ok(
    (SELECT push_token IS NULL FROM notify.device WHERE id = (SELECT id FROM dev LIMIT 1)),
    'a revoked device loses its push token'
);
CREATE TEMP TABLE flags (n integer, v boolean);
DO $$
DECLARE r boolean;
BEGIN
    CALL notify.pr_revoke_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(21), r);
    INSERT INTO flags VALUES (1, r);
    CALL notify.pr_revoke_device('0192f000-0000-7000-8000-0000000003e1', pg_temp.hash(99), r);
    INSERT INTO flags VALUES (2, r);
END
$$;
SELECT is((SELECT string_agg(v::text, ',' ORDER BY n) FROM flags), 'true,false', 'revoke: own device found; unknown installation is a no-op');
SELECT ok(
    (SELECT revoked_at IS NOT NULL AND push_token IS NULL FROM notify.device WHERE installation_id = pg_temp.hash(21)),
    'the revoked device is marked and its token wiped'
);

-- ===== Preferences =====
SELECT is(
    notify.fn_notification_preferences('0192f000-0000-7000-8000-0000000003e1') ->> 'daily_checkin',
    'false', 'defaults: daily check-in off'
);
SELECT is(
    (SELECT count(*)::integer FROM jsonb_object_keys(notify.fn_notification_preferences('0192f000-0000-7000-8000-0000000003e1'))),
    12, 'the 12 toggles are returned'
);
SELECT lives_ok(
    $$CALL notify.pr_set_notification_preferences('0192f000-0000-7000-8000-0000000003e1', '{"goal_completions": true, "streak_milestones": true, "health_insights": false, "hydration_reminders": true, "nutrition_reminders": false, "sleep_reminders": true, "daily_checkin": true, "health_profile_reminders": true, "connection_requests": true, "connection_activity": true, "reports_ready": true, "subscription_payments": true}')$$,
    'all 12 toggles saved'
);
SELECT is(
    (SELECT j ->> 'nutrition_reminders' || ',' || (j ->> 'daily_checkin') FROM notify.fn_notification_preferences('0192f000-0000-7000-8000-0000000003e1') AS j),
    'false,true', 'preferences read back'
);
SELECT throws_ok(
    $$CALL notify.pr_set_notification_preferences('0192f000-0000-7000-8000-0000000003e1', '{"goal_completions": true}')$$,
    '22023', NULL, 'a partial object is refused (PUT replaces all)'
);
SELECT throws_ok(
    $$CALL notify.pr_set_notification_preferences('0192f000-0000-7000-8000-0000000003e1', '{"goal_completions": true, "streak_milestones": true, "health_insights": false, "hydration_reminders": true, "nutrition_reminders": false, "sleep_reminders": true, "daily_checkin": true, "health_profile_reminders": true, "connection_requests": true, "connection_activity": true, "reports_ready": true, "subscription_payments": true, "role": "admin"}')$$,
    '22023', NULL, 'an unknown key is refused, never ignored'
);
SELECT throws_ok(
    $$CALL notify.pr_set_notification_preferences('0192f000-0000-7000-8000-0000000003e1', '{"goal_completions": "yes", "streak_milestones": true, "health_insights": false, "hydration_reminders": true, "nutrition_reminders": false, "sleep_reminders": true, "daily_checkin": true, "health_profile_reminders": true, "connection_requests": true, "connection_activity": true, "reports_ready": true, "subscription_payments": true}')$$,
    '22023', NULL, 'non-boolean values are refused'
);

-- ===== Reminder schedules =====
SELECT is(
    (SELECT string_agg(reminder_type || ':' || enabled || ':' || saved, ',') FROM notify.fn_reminders('0192f000-0000-7000-8000-0000000003e1')),
    'hydration:false:false,nutrition:false:false,sleep:false:false,daily_checkin:false:false,health_profile:false:false',
    'unsaved schedules come back disabled (opt-in)'
);
SELECT is(
    (SELECT interval_min FROM notify.fn_reminders('0192f000-0000-7000-8000-0000000003e1') WHERE reminder_type = 'hydration'),
    120::smallint, 'hydration suggests every 2 hours'
);
SELECT lives_ok(
    $$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "hydration", "enabled": true, "interval_min": 120}, {"type": "nutrition", "enabled": true, "times": ["20:00", "08:30"]}, {"type": "sleep", "enabled": true, "times": ["22:45"]}]')$$,
    'schedules saved'
);
SELECT is(
    (SELECT array_to_string(times, ',') FROM notify.fn_reminders('0192f000-0000-7000-8000-0000000003e1') WHERE reminder_type = 'nutrition'),
    '08:30,20:00', 'times are sorted HH:MM'
);
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "hydration", "enabled": true, "interval_min": 30}]')$$, '22023', NULL, 'an interval below 60 is refused');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "nutrition", "enabled": true, "times": ["8:30"]}]')$$, '22023', NULL, 'times must be HH:MM');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "nutrition", "enabled": true, "times": ["08:30", "08:30"]}]')$$, '22023', NULL, 'times must be distinct');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "nutrition", "enabled": true, "times": ["<b>"]}]')$$, '22023', NULL, 'markup in a time is refused');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "nutrition", "enabled": true}]')$$, '22023', NULL, 'an enabled reminder needs times or an interval');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "nutrition", "enabled": true, "times": ["08:00"], "interval_min": 60}]')$$, '22023', NULL, 'times and an interval together are refused');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "nutrition", "enabled": true, "times": ["08:00"]}, {"type": "nutrition", "enabled": false}]')$$, '22023', NULL, 'a type twice is refused');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "marketing", "enabled": false}]')$$, '22023', NULL, 'an unknown type is refused');
SELECT throws_ok($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', '[{"type": "sleep", "enabled": false, "user_id": "x"}]')$$, '22023', NULL, 'unknown fields are refused');
SELECT throws_ok(
    format($$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e1', %L)$$,
        jsonb_build_array(jsonb_build_object('type', 'nutrition', 'enabled', TRUE, 'times',
            (SELECT jsonb_agg(to_char(time '06:00' + n * interval '1 minute', 'HH24:MI')) FROM generate_series(1, 13) AS n)))),
    '22023', NULL, 'more than 12 times are refused'
);
SELECT throws_ok(
    $$CALL notify.pr_set_reminders('0192f000-0000-7000-8000-0000000003e2', '[]')$$,
    '42501', NULL, 'nobody can change another user''s reminders'
);

-- ===== Worker fan-out =====
SELECT set_config('app.user_id', '', TRUE);
-- u2 (London) and u3 (pending deletion) have devices and a nutrition reminder at 08:30 too.
INSERT INTO notify.device (user_id, installation_id, platform, push_token, app_version) VALUES
('0192f000-0000-7000-8000-0000000003e2', pg_temp.hash(50), 'ios', pg_temp.token(50), '1.0.0'),
('0192f000-0000-7000-8000-0000000003e3', pg_temp.hash(51), 'ios', pg_temp.token(51), '1.0.0');
INSERT INTO notify.reminder (user_id, type, enabled, times) VALUES
('0192f000-0000-7000-8000-0000000003e2', 'nutrition', TRUE, '{08:30}'),
('0192f000-0000-7000-8000-0000000003e3', 'nutrition', TRUE, '{08:30}');

SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '09:00'))),
    9, 'interval: 2 h after wake (09:00) reaches the 9 devices of u1 that still have a token'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '09:30'))),
    0, 'nothing is due at 09:30 IST'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '07:00'))),
    0, 'no interval reminder at wake time itself'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '08:30')) WHERE user_id = '0192f000-0000-7000-8000-0000000003e1'),
    0, 'u1 turned nutrition reminders off in preferences'
);
SELECT is(
    (SELECT string_agg(DISTINCT reminder_type, ',') FROM ops.fn_due_reminders(pg_temp.local('Europe/London', '08:30')) WHERE user_id = '0192f000-0000-7000-8000-0000000003e2'),
    'nutrition', 'times are local: u2 is reminded at 08:30 London time'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Europe/London', '08:30')) WHERE user_id = '0192f000-0000-7000-8000-0000000003e3'),
    0, 'accounts that are not active get nothing'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '22:45'))),
    0, 'quiet hours (22:30-07:00) silence the 22:45 sleep reminder'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '22:45'), '23:00', '07:00')),
    9, 'with quiet hours from 23:00 the sleep reminder goes out'
);
INSERT INTO hydration.daily_summary (user_id, local_date, goal_completed_at)
VALUES ('0192f000-0000-7000-8000-0000000003e1', common.fn_local_date('Asia/Kolkata'), now());
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '09:00'))),
    0, 'hydration reminders stop once today''s goal is completed'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_day_ending_soon(pg_temp.local('Asia/Kolkata', '20:00'))),
    0, 'no day-ending nudge after the goal is completed'
);
DELETE FROM hydration.daily_summary WHERE user_id = '0192f000-0000-7000-8000-0000000003e1';
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_day_ending_soon(pg_temp.local('Asia/Kolkata', '20:00'))),
    9, 'bedtime 23:00: the day-ending nudge goes out at 20:00 (3 h before)'
);
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_day_ending_soon(pg_temp.local('Asia/Kolkata', '20:15'))),
    0, 'only in the first 15-minute slot'
);
SELECT ok(
    (SELECT bool_and(push_token IS NOT NULL) FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '09:00'))),
    'the worker receives encrypted tokens only (decrypted by the worker)'
);
DO $$
DECLARE v uuid := (SELECT id FROM notify.device WHERE installation_id = pg_temp.hash(12));
BEGIN
    CALL ops.pr_revoke_push_token(v);
END
$$;
SELECT is(
    (SELECT count(*)::integer FROM ops.fn_due_reminders(pg_temp.local('Asia/Kolkata', '09:00'))),
    8, 'a token FCM reported as unregistered is wiped and skipped'
);
SELECT ok(ops.fn_is_quiet('23:30', '22:30', '07:00') AND ops.fn_is_quiet('06:59', '22:30', '07:00') AND NOT ops.fn_is_quiet('07:00', '22:30', '07:00'), 'quiet hours wrap midnight');

-- ===== Grants: the fan-out is worker-only =====
SELECT ok(has_function_privilege('app_worker', 'ops.fn_due_reminders(timestamptz, time, time)', 'EXECUTE'), 'the worker may compute due reminders');
SELECT ok(NOT has_function_privilege('app_rw', 'ops.fn_due_reminders(timestamptz, time, time)', 'EXECUTE'), 'the API role may not (clients cannot trigger reminders)');
SELECT ok(NOT has_function_privilege('app_rw', 'ops.fn_day_ending_soon(timestamptz, numeric, integer, time, time)', 'EXECUTE'), 'nor the day-ending nudge');
SELECT ok(NOT has_function_privilege('app_rw', 'ops.pr_revoke_push_token(uuid)', 'EXECUTE'), 'nor wipe push tokens');
SELECT ok(has_function_privilege('app_rw', 'notify.pr_register_device(uuid, uuid, common.code, common.opaque_token, common.app_version, uuid)', 'EXECUTE'), 'the API role registers devices');

SELECT * FROM finish();
ROLLBACK;
