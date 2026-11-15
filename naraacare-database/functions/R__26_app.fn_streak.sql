-- Streak (Session 14, doc 06 section 5, OQ-40). A day is active when app.user_activity_day has any of
-- hydration / nutrition / sleep for it; the day key is the local date stored when the entry was
-- written, so a timezone change never breaks a streak.
--   * fn_streak_runs (internal): gaps-and-islands over the active days -> current run (ending today,
--     or yesterday while today has no log yet), longest run, last active day.
--   * fn_streak: GET /me/streak -> counters, "Streak Broken" flag and the active days of one month
--     plus the last 7 days (the week strip may cross a month boundary).
-- app.user_streak is a cache for GET /me; app.pr_recompute_streak refreshes it when a new active day
-- is written. Reads never trust it for "today": a stale cache (no log since yesterday) reads as 0.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION app.fn_streak_runs(p_user_id uuid, p_today date)
RETURNS TABLE (current_streak integer, longest_streak integer, last_active_date date)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    WITH active AS (
        SELECT d.local_date
        FROM app.user_activity_day AS d
        WHERE d.user_id = p_user_id
          AND d.local_date <= p_today
          AND (d.has_hydration OR d.has_nutrition OR d.has_sleep)
    ),
    islands AS (
        SELECT a.local_date - (row_number() OVER (ORDER BY a.local_date))::integer AS grp, a.local_date
        FROM active AS a
    ),
    runs AS (
        SELECT max(i.local_date) AS run_end, count(*)::integer AS run_len
        FROM islands AS i
        GROUP BY i.grp
    )
    SELECT
        coalesce(max(r.run_len) FILTER (WHERE r.run_end >= p_today - 1), 0),
        coalesce(max(r.run_len), 0),
        max(r.run_end)
    FROM runs AS r;
$$;
COMMENT ON FUNCTION app.fn_streak_runs(uuid, date) IS
'Internal: current run (ending today or yesterday), longest run and last active day';
REVOKE ALL ON FUNCTION app.fn_streak_runs(uuid, date) FROM public;

CREATE OR REPLACE FUNCTION app.fn_streak(p_user_id uuid, p_month date DEFAULT NULL)
RETURNS TABLE (
    current_streak integer,
    longest_streak integer,
    broken_yesterday boolean,
    today date,
    active_days date []
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_today date;
    v_month date;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT common.fn_local_date(coalesce(p.timezone, 'Asia/Kolkata')) INTO v_today
    FROM app.user_profile AS p WHERE p.user_id = p_user_id;
    v_today := coalesce(v_today, common.fn_local_date('Asia/Kolkata'));
    v_month := date_trunc('month', coalesce(p_month, v_today))::date;
    IF v_month > v_today OR v_month < date '2026-01-01' THEN
        RAISE EXCEPTION 'month out of range' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    RETURN QUERY
    SELECT
        r.current_streak,
        r.longest_streak,
        -- "Streak Broken": nothing yesterday or today, but the day before was active (the streak
        -- ended yesterday), as in the Figma "Profile/ Streak/ Break" frame.
        -- Never NULL: an account with no active day yet has last_active_date NULL.
        coalesce(r.current_streak = 0 AND r.last_active_date = v_today - 2, FALSE),
        v_today,
        coalesce((
            SELECT array_agg(d.local_date ORDER BY d.local_date)
            FROM app.user_activity_day AS d
            WHERE d.user_id = p_user_id
              AND (d.has_hydration OR d.has_nutrition OR d.has_sleep)
              AND (
                  d.local_date BETWEEN v_month AND (v_month + interval '1 month - 1 day')::date
                  OR d.local_date BETWEEN v_today - 6 AND v_today
              )
        ), ARRAY[]::date [])
    FROM app.fn_streak_runs(p_user_id, v_today) AS r;
END
$$;
COMMENT ON FUNCTION app.fn_streak(uuid, date) IS
'GET /me/streak: current / longest streak, broken flag, active days of a month and the last 7 days';
REVOKE ALL ON FUNCTION app.fn_streak(uuid, date) FROM public;
GRANT EXECUTE ON FUNCTION app.fn_streak(uuid, date) TO app_rw;
