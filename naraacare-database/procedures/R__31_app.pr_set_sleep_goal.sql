-- PUT /me/sleep-goal (doc 04 section 2.6, doc 06 section 4). The user's own goal (240..720 minutes)
-- replaces the default for their age. Today's sleep summary is rebuilt with the new goal; earlier
-- days keep the goal they were scored with. Allowed on every tier (the goal is part of the profile;
-- reading sleep needs STAR).
-- Errors: 42501 not the actor, 22023 out of range, P0001 ONBOARDING_INCOMPLETE.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_set_sleep_goal(p_user_id uuid, p_goal_min integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_goal_min IS NULL OR p_goal_min NOT BETWEEN 240 AND 720 THEN
        RAISE EXCEPTION 'sleep goal must be 240..720 minutes' USING ERRCODE = '22023', DETAIL = 'GOAL_INVALID';
    END IF;
    UPDATE app.user_profile AS p
    SET sleep_goal_min = p_goal_min, updated_at = now()
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL
    RETURNING p.timezone INTO v_timezone;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    CALL sleep.pr_refresh_daily_summary(p_user_id, common.fn_local_date(v_timezone));
END
$$;

COMMENT ON PROCEDURE app.pr_set_sleep_goal (uuid, integer) IS
'Set the user''s sleep goal (240-720 min); today''s sleep summary is rescored';
REVOKE ALL ON PROCEDURE app.pr_set_sleep_goal(uuid, integer) FROM public;
GRANT EXECUTE ON PROCEDURE app.pr_set_sleep_goal(uuid, integer) TO app_rw;
