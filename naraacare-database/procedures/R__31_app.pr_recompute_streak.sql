-- Streak cache and milestones (Session 14, doc 06 section 5).
--   * pr_recompute_streak (internal): refreshes app.user_streak from the active days and, when the
--     current streak has just passed a milestone (3, 7, 14, 30, 60, 100, 365 days), writes one in-app
--     notification for the highest one passed (template streak_milestone, params {days}). The push follows the
--     streak_milestones preference in the worker; the in-app row is always written.
--   * trg_fn_activity_day_streak: runs it when a new active day row appears (every tracking procedure
--     writes app.user_activity_day), so no tracking procedure has to remember to call it.
-- Day rollover needs no job: readers treat a cache whose last active day is before yesterday as 0.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_recompute_streak(p_user_id uuid, p_today date)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_previous integer;
    v_current integer;
    v_longest integer;
    v_last date;
    v_milestone integer;
BEGIN
    SELECT CASE WHEN s.last_active_date >= p_today - 1 THEN s.current_streak ELSE 0 END
    INTO v_previous
    FROM app.user_streak AS s WHERE s.user_id = p_user_id;
    SELECT r.current_streak, r.longest_streak, r.last_active_date INTO v_current, v_longest, v_last
    FROM app.fn_streak_runs(p_user_id, p_today) AS r;

    INSERT INTO app.user_streak (user_id, current_streak, longest_streak, last_active_date, updated_at)
    VALUES (p_user_id, v_current, v_longest, v_last, now())
    ON CONFLICT (user_id) DO UPDATE SET
        current_streak = excluded.current_streak,
        longest_streak = excluded.longest_streak,
        last_active_date = excluded.last_active_date,
        updated_at = now();

    -- Several days can arrive at once (offline entries, backfilled days): notify the highest
    -- milestone crossed by this change, once.
    SELECT max(m) INTO v_milestone
    FROM unnest(ARRAY[3, 7, 14, 30, 60, 100, 365]) AS m
    WHERE m > coalesce(v_previous, 0) AND m <= v_current;
    IF v_milestone IS NOT NULL THEN
        INSERT INTO notify.notification (user_id, category, template_code, params, deep_link)
        VALUES (
            p_user_id, 'progress', 'streak_milestone', jsonb_build_object('days', v_milestone),
            'naraacare://profile/streak'
        );
    END IF;
END
$$;
COMMENT ON PROCEDURE app.pr_recompute_streak(uuid, date) IS
'Internal: refresh app.user_streak; in-app notification when a streak milestone is reached';
REVOKE ALL ON PROCEDURE app.pr_recompute_streak(uuid, date) FROM public;

CREATE OR REPLACE FUNCTION app.trg_fn_activity_day_streak()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_today date;
BEGIN
    SELECT common.fn_local_date(p.timezone) INTO v_today
    FROM app.user_profile AS p WHERE p.user_id = NEW.user_id;
    CALL app.pr_recompute_streak(NEW.user_id, coalesce(v_today, common.fn_local_date('Asia/Kolkata')));
    RETURN NULL;
END
$$;
COMMENT ON FUNCTION app.trg_fn_activity_day_streak() IS
'Trigger: recompute the streak when a new active day is recorded';
REVOKE ALL ON FUNCTION app.trg_fn_activity_day_streak() FROM public;
