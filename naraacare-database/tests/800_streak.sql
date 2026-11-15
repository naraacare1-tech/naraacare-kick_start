-- Streak (Session 14; doc 06 section 5, OQ-40): consecutive active days, a gap resets the current run,
-- yesterday still counts until today is logged, the longest run is kept, the "broken" flag, one
-- milestone notification for the highest milestone crossed (even when several days arrive at once),
-- active days are keyed by the stored local date (a timezone change does not break the run), IDOR.
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-000000008001', 'st1@example.test', 'active'),
('0192f000-0000-7000-8000-000000008002', 'st2@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at) VALUES
('0192f000-0000-7000-8000-000000008001', 6, now()),
('0192f000-0000-7000-8000-000000008002', 6, now());

CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql AS $$ SELECT common.fn_local_date('Asia/Kolkata') $$;
CREATE FUNCTION pg_temp.active(p_user text, p_days_back integer[]) RETURNS void LANGUAGE sql AS $$
    INSERT INTO app.user_activity_day (user_id, local_date, has_hydration)
    SELECT p_user::uuid, pg_temp.today() - d, TRUE FROM unnest(p_days_back) AS d
    ON CONFLICT DO NOTHING
$$;
CREATE FUNCTION pg_temp.streak(p_user text) RETURNS integer[] LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    PERFORM set_config('app.user_id', p_user, TRUE);
    SELECT * INTO r FROM app.fn_streak(p_user::uuid);
    RETURN ARRAY[r.current_streak, r.longest_streak, CASE WHEN r.broken_yesterday THEN 1 ELSE 0 END];
END
$$;
CREATE FUNCTION pg_temp.milestones(p_user text) RETURNS text[] LANGUAGE sql AS $$
    SELECT coalesce(array_agg(n.params ->> 'days' ORDER BY n.created_at, n.id), '{}')
    FROM notify.notification AS n
    WHERE n.user_id = p_user::uuid AND n.template_code = 'streak_milestone'
$$;
CREATE FUNCTION pg_temp.u1() RETURNS text LANGUAGE sql AS $$ SELECT '0192f000-0000-7000-8000-000000008001' $$;

SELECT is(pg_temp.streak(pg_temp.u1()), ARRAY[0, 0, 0], 'no activity: 0, 0');

-- Days 10..8 ago (a 3-day run), a gap, then yesterday and the day before.
SELECT pg_temp.active(pg_temp.u1(), ARRAY[10, 9, 8]);
SELECT is(pg_temp.streak(pg_temp.u1()), ARRAY[0, 3, 0], 'an old run is the longest but not current');
SELECT pg_temp.active(pg_temp.u1(), ARRAY[2, 1]);
SELECT is(pg_temp.streak(pg_temp.u1()), ARRAY[2, 3, 0], 'yesterday still counts while today has no log yet');
SELECT pg_temp.active(pg_temp.u1(), ARRAY[0]);
SELECT is(pg_temp.streak(pg_temp.u1()), ARRAY[3, 3, 0], 'logging today extends the run');

-- A sleep-only or nutrition-only day counts too; a row with no activity flag does not.
INSERT INTO app.user_activity_day (user_id, local_date) VALUES (pg_temp.u1()::uuid, pg_temp.today() - 3);
SELECT is(pg_temp.streak(pg_temp.u1()), ARRAY[3, 3, 0], 'a day with no logged category is not active');
UPDATE app.user_activity_day SET has_sleep = TRUE WHERE user_id = pg_temp.u1()::uuid AND local_date = pg_temp.today() - 3;
SELECT is((pg_temp.streak(pg_temp.u1()))[1], 4, 'a sleep-only day is active');

-- Broken: active the day before yesterday but not yesterday or today.
SELECT pg_temp.active('0192f000-0000-7000-8000-000000008002', ARRAY[5, 4, 3, 2]);
SELECT is(pg_temp.streak('0192f000-0000-7000-8000-000000008002'), ARRAY[0, 4, 1], 'missing yesterday breaks the streak');

-- ===== Milestones =====
-- u1 crossed 3 (today) above: one notification "3".
SELECT is(pg_temp.milestones(pg_temp.u1()), ARRAY['3'], 'crossing 3 days writes one milestone');
-- A backfilled week (days 4..9 ago) joins everything into one 11-day run at once: 7 is the highest crossed.
SELECT pg_temp.active(pg_temp.u1(), ARRAY[4, 5, 6, 7]);
SELECT is((pg_temp.streak(pg_temp.u1()))[1], 11, 'backfilled days join the runs');
SELECT is(pg_temp.milestones(pg_temp.u1()), ARRAY['3', '7'], 'several days at once: only the highest milestone passed');

-- Timezone change: days already stored keep their local date, so the run survives.
UPDATE app.user_profile SET timezone = 'America/New_York' WHERE user_id = pg_temp.u1()::uuid;
SELECT ok((pg_temp.streak(pg_temp.u1()))[1] >= 10, 'changing timezone does not break the streak');

-- ===== Ownership =====
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000008002', TRUE);
SELECT throws_ok(
    $$SELECT * FROM app.fn_streak('0192f000-0000-7000-8000-000000008001')$$,
    '42501', NULL, 'nobody reads another user''s streak'
);

SELECT * FROM finish();
ROLLBACK;
