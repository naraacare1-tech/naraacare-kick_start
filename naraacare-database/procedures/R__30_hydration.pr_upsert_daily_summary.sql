-- Called by GET /hydration/status after the API computed the status (doc 06 section 3.8, Session 09
-- step 2). Stores the day's need and food water for reports, and sets goal_completed_at the first
-- time the goal is reached (never cleared: the "goal completed" feed event fires once a day).
-- o_first_completion = TRUE only on the call that set it; that call writes the 'goal_completed' feed
-- event and the circle notifications (Session 12), so they fire once a day.
-- Days older than 7 days are left alone (they can no longer change, OQ-53).
-- Errors: 42501 not the actor, 22023 out of range (table CHECKs: need 1500..6000).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE hydration.pr_upsert_daily_summary(
    p_user_id uuid,
    p_date date,
    p_daily_need_ml integer,
    p_food_water_ml numeric,
    p_goal_completed boolean,
    p_calc_version common.version_label,
    INOUT o_first_completion boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_completed timestamptz;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    o_first_completion := FALSE;
    SELECT p.timezone INTO v_timezone FROM app.user_profile AS p WHERE p.user_id = p_user_id;
    IF p_date IS NULL OR p_date < common.fn_local_date(v_timezone) - 7
       OR p_date > common.fn_local_date(v_timezone) THEN
        RETURN;
    END IF;

    CALL hydration.pr_lock_daily_summary(p_user_id, p_date);
    SELECT d.goal_completed_at INTO v_completed
    FROM hydration.daily_summary AS d WHERE d.user_id = p_user_id AND d.local_date = p_date;

    UPDATE hydration.daily_summary AS d
    SET daily_need_ml = p_daily_need_ml,
        food_water_ml = round(coalesce(p_food_water_ml, 0), 1),
        calc_version = p_calc_version,
        goal_completed_at = CASE WHEN coalesce(p_goal_completed, FALSE) THEN coalesce(d.goal_completed_at, now())
                                 ELSE d.goal_completed_at END,
        updated_at = now()
    WHERE d.user_id = p_user_id AND d.local_date = p_date;

    o_first_completion := v_completed IS NULL AND coalesce(p_goal_completed, FALSE);
    IF o_first_completion AND p_date = common.fn_local_date(v_timezone) THEN
        CALL social.pr_emit_activity(
            p_user_id, 'hydration', 'goal_completed', jsonb_build_object('goal_ml', p_daily_need_ml)
        );
    END IF;
END
$$;

COMMENT ON PROCEDURE hydration.pr_upsert_daily_summary (uuid, date, integer, numeric, boolean, common.version_label, boolean) IS
'Store the day''s need, food water and first goal completion (computed by the API status engine)';
REVOKE ALL ON PROCEDURE hydration.pr_upsert_daily_summary(uuid, date, integer, numeric, boolean, common.version_label, boolean)
FROM public;
GRANT EXECUTE ON PROCEDURE hydration.pr_upsert_daily_summary(uuid, date, integer, numeric, boolean, common.version_label, boolean)
TO app_rw;
