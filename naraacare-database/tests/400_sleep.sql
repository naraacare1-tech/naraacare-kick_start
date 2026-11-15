-- Sleep (Session 10; doc 06 section 4, OQ-23): STAR only, counted minutes and score from the calc
-- constants (15 min onset + 15 min wake buffers, wakings subtracted), 16-hour cap, overlap refused,
-- idempotent create, entries belong to their wake date, last-2 edit window, If-Match, IDOR.
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-000000004001', 'sl1@example.test', 'active'),
('0192f000-0000-7000-8000-000000004002', 'sl2@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at) VALUES
('0192f000-0000-7000-8000-000000004001', 6, now()),
('0192f000-0000-7000-8000-000000004002', 6, now());
-- 4001 is STAR, 4002 STANDARD.
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-000000004001', 'star', 'promo', now() - interval '1 day', now() + interval '30 days');

CREATE FUNCTION pg_temp.id(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(16640 + n), 12, '0'))::uuid
$$;
-- Local (Asia/Kolkata) time on day D - p_days_back, p_hours after midnight (negative = the evening before).
CREATE FUNCTION pg_temp.at(p_days_back integer, p_hours numeric) RETURNS timestamptz LANGUAGE sql AS $$
    SELECT ((common.fn_local_date('Asia/Kolkata') - p_days_back)::timestamp + p_hours * interval '1 hour')
        AT TIME ZONE 'Asia/Kolkata'
$$;
CREATE FUNCTION pg_temp.day(p_days_back integer) RETURNS date LANGUAGE sql AS $$
    SELECT common.fn_local_date('Asia/Kolkata') - p_days_back
$$;
CREATE FUNCTION pg_temp.log(p_user uuid, p_id uuid, p_start timestamptz, p_wake timestamptz, p_wakings jsonb DEFAULT '[]')
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s text; d date;
BEGIN
    CALL sleep.pr_log_entry(p_user, p_id, p_start, p_wake, p_wakings, s, d);
    RETURN s || ' ' || d;
END
$$;
CREATE FUNCTION pg_temp.summary(p_days_back integer) RETURNS jsonb LANGUAGE sql AS $$
    SELECT sleep.fn_summary('0192f000-0000-7000-8000-000000004001', pg_temp.day(p_days_back))
$$;

-- ===== Tier =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000004002', TRUE);
SELECT throws_ok(
    $$SELECT pg_temp.log('0192f000-0000-7000-8000-000000004002', pg_temp.id(1), pg_temp.at(1, -1), pg_temp.at(1, 7))$$,
    'P0001', NULL, 'STANDARD cannot log sleep'
);
SELECT throws_ok(
    $$SELECT sleep.fn_summary('0192f000-0000-7000-8000-000000004002', NULL)$$,
    'P0001', NULL, 'STANDARD cannot read the sleep summary'
);

SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000004001', TRUE);
CREATE FUNCTION pg_temp.u1() RETURNS uuid LANGUAGE sql AS $$ SELECT '0192f000-0000-7000-8000-000000004001'::uuid $$;

-- ===== Counting (doc 06 section 4) =====
-- DOC example: 8 h in bed -> 480 - 15 - 15 = 450 min, 94 % of the 480-minute goal, "good".
SELECT is(
    pg_temp.log(pg_temp.u1(), pg_temp.id(10), pg_temp.at(1, -2), pg_temp.at(1, 6)),
    'created ' || pg_temp.day(1), 'a night crossing midnight belongs to its wake date'
);
SELECT is(
    (SELECT ARRAY[(s ->> 'counted_min')::int, (s ->> 'score_pct')::int, (s ->> 'goal_min')::int]
     FROM pg_temp.summary(1) AS s),
    ARRAY[450, 94, 480], 'DOC example: 8 h -> 450 min, 94 %'
);
SELECT is(pg_temp.summary(1) ->> 'label', 'good', '94 % is good');

-- FIG: 7 h 45 counted (8 h 15 in bed) -> 97 %.
SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(11), pg_temp.at(2, -2.25), pg_temp.at(2, 6));
SELECT is(
    (SELECT ARRAY[(s ->> 'counted_min')::int, (s ->> 'score_pct')::int] FROM pg_temp.summary(2) AS s),
    ARRAY[465, 97], 'FIG: 7 h 45 counted -> 97 %'
);

-- Doc 06 example: one waking 02:00-02:20, loss (02:20 + 10) - 02:00 = 30 -> 420 min, 88 %, "fair".
SELECT pg_temp.log(
    pg_temp.u1(), pg_temp.id(12), pg_temp.at(3, -2), pg_temp.at(3, 6),
    jsonb_build_array(jsonb_build_object('woke_at', pg_temp.at(3, 2), 'back_asleep_at', pg_temp.at(3, 2) + interval '20 minutes'))
);
SELECT is(
    (SELECT ARRAY[(s ->> 'counted_min')::int, (s ->> 'score_pct')::int] FROM pg_temp.summary(3) AS s),
    ARRAY[420, 88], 'one 20-minute waking (+10 min to fall asleep) -> 420 min, 88 %'
);
SELECT is(pg_temp.summary(3) ->> 'label', 'fair', '88 % is fair');

-- Several entries on one day are summed (a nap): 2 h nap -> 90 counted, day total 450 + 90.
SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(13), pg_temp.at(1, 13), pg_temp.at(1, 15));
SELECT is((pg_temp.summary(1) ->> 'counted_min')::int, 540, 'a nap is added to the day');
SELECT is(jsonb_array_length(pg_temp.summary(1) -> 'entries'), 2, 'both entries listed');

-- Buffers larger than the interval count as 0, never negative.
SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(14), pg_temp.at(4, 13), pg_temp.at(4, 13.333));
SELECT is((pg_temp.summary(4) ->> 'counted_min')::int, 0, '20 minutes in bed counts 0');

-- ===== Limits =====
SELECT is(
    split_part(pg_temp.log(pg_temp.u1(), pg_temp.id(15), pg_temp.at(5, -10), pg_temp.at(5, 6)), ' ', 1),
    'created', 'exactly 16 hours is accepted'
);
SELECT throws_ok(
    $$SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(16), pg_temp.at(6, -10) - interval '1 minute', pg_temp.at(6, 6))$$,
    '22023', NULL, '16 hours and 1 minute is refused'
);
SELECT throws_ok(
    $$SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(17), pg_temp.at(6, 7), pg_temp.at(6, 6))$$,
    '22023', NULL, 'wake before sleep start is refused'
);
SELECT throws_ok(
    $$SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(18), now() + interval '1 hour', now() + interval '2 hours')$$,
    '22023', NULL, 'sleep in the future is refused'
);
SELECT throws_ok(
    $$SELECT pg_temp.log(pg_temp.u1(), pg_temp.id(19), pg_temp.at(1, 1), pg_temp.at(1, 3))$$,
    'P0001', NULL, 'an entry overlapping another is refused (SLEEP_OVERLAP)'
);
SELECT is(
    split_part(pg_temp.log(pg_temp.u1(), pg_temp.id(10), pg_temp.at(1, -2), pg_temp.at(1, 6)), ' ', 1),
    'duplicate', 'the same client id again is a duplicate, not a second entry'
);

-- ===== Editing: last 2 entries, If-Match =====
-- Most recent by wake time: id 13 (nap, D-1 15:00) and id 10 (D-1 06:00); id 11 (D-2) is older.
SELECT throws_ok(
    $$CALL sleep.pr_update_entry(pg_temp.u1(), pg_temp.id(11), 1, pg_temp.at(2, -2), pg_temp.at(2, 6), '[]', NULL)$$,
    'P0001', NULL, 'only the last 2 entries can be edited (EDIT_WINDOW_CLOSED)'
);
SELECT throws_ok(
    $$CALL sleep.pr_update_entry(pg_temp.u1(), pg_temp.id(13), 7, pg_temp.at(1, 13), pg_temp.at(1, 14), '[]', NULL)$$,
    'P0001', NULL, 'a stale version is refused (VERSION_CONFLICT)'
);
DO $$
DECLARE v integer;
BEGIN
    CALL sleep.pr_update_entry(pg_temp.u1(), pg_temp.id(13), 1, pg_temp.at(1, 13), pg_temp.at(1, 14), '[]', v);
    CREATE TEMP TABLE upd AS SELECT v AS version;
END $$;
SELECT is((SELECT version FROM upd), 2, 'an edit bumps the version');
SELECT is((pg_temp.summary(1) ->> 'counted_min')::int, 480, 'the day is recomputed after the edit (450 + 30)');

-- ===== Another user's entry (IDOR) =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000004002', TRUE);
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-000000004002', 'star', 'promo', now() - interval '1 day', now() + interval '30 days');
SELECT throws_ok(
    $$CALL sleep.pr_delete_entry('0192f000-0000-7000-8000-000000004002', pg_temp.id(13), 2)$$,
    '42501', NULL, 'another user cannot delete the entry (404)'
);
SELECT throws_ok(
    $$SELECT sleep.fn_summary('0192f000-0000-7000-8000-000000004001', NULL)$$,
    '42501', NULL, 'nobody reads another user''s summary'
);
SELECT is(
    (SELECT count(*)::int FROM sleep.entry WHERE id = pg_temp.id(13)), 1, 'the entry is untouched'
);

SELECT * FROM finish();
ROLLBACK;
