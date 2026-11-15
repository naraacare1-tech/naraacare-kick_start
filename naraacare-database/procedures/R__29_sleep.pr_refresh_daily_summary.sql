-- Internal: rebuild one day's sleep.daily_summary from the non-deleted entries whose wake time falls on
-- that local date (naps included, doc 06 section 4). goal = the user's sleep goal, else the default
-- for their age (ref.sleep_goal_by_age); score = min(100, round half-up(total / goal x 100)). A day
-- with no entries left has no summary row.
-- Not granted to any login role: called from the definer procedures (run as api_definer, RLS on).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE sleep.pr_refresh_daily_summary(p_user_id uuid, p_date date)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_total integer;
    v_count integer;
    v_goal integer;
BEGIN
    SELECT coalesce(sum(e.counted_min), 0), count(*) INTO v_total, v_count
    FROM sleep.entry AS e
    WHERE e.user_id = p_user_id AND e.wake_local_date = p_date AND e.deleted_at IS NULL;

    IF v_count = 0 THEN
        DELETE FROM sleep.daily_summary AS d WHERE d.user_id = p_user_id AND d.local_date = p_date;
        RETURN;
    END IF;

    SELECT coalesce(p.sleep_goal_min, (
        SELECT g.goal_min FROM ref.sleep_goal_by_age AS g
        WHERE p.age_years BETWEEN g.min_age AND g.max_age
    ), 480)
    INTO v_goal
    FROM app.user_profile AS p WHERE p.user_id = p_user_id;

    INSERT INTO sleep.daily_summary AS d (user_id, local_date, counted_min, goal_min, score_pct)
    VALUES (
        p_user_id, p_date, least(v_total, 1440), v_goal,
        least(100, round(v_total * 100.0 / v_goal))::smallint
    )
    ON CONFLICT (user_id, local_date) DO UPDATE SET
        counted_min = excluded.counted_min, goal_min = excluded.goal_min, score_pct = excluded.score_pct,
        updated_at = now();
END
$$;

COMMENT ON PROCEDURE sleep.pr_refresh_daily_summary (uuid, date) IS
'Internal: rebuild a day''s sleep total, goal and score from its entries';
REVOKE ALL ON PROCEDURE sleep.pr_refresh_daily_summary(uuid, date) FROM public;
