-- PATCH /me/profile (doc 04 section 2.2). NULL parameters leave the column unchanged. When anything that
-- feeds the calculations changes, the API recomputes and passes p_snapshot, which replaces TODAY's
-- snapshot only; past days keep their targets (doc 06 section 1). Without p_snapshot no target changes.
-- With it, today's nutrition summary (calorie target and allowance) is refreshed in the same transaction.
-- Errors: P0001 ONBOARDING_INCOMPLETE (use the onboarding steps first); table CHECK/FK errors.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_update_profile(
    p_user_id uuid,
    p_full_name common.safe_text DEFAULT NULL,
    p_biological_sex common.code DEFAULT NULL,
    p_avatar_code common.code DEFAULT NULL,
    p_age_years smallint DEFAULT NULL,
    p_height_cm numeric DEFAULT NULL,
    p_weight_kg numeric DEFAULT NULL,
    p_target_weight_kg numeric DEFAULT NULL,
    p_weight_goal_code common.code DEFAULT NULL,
    p_activity_level_code common.code DEFAULT NULL,
    p_body_type_code common.code DEFAULT NULL,
    p_medical_conditions common.code[] DEFAULT NULL,
    p_snapshot jsonb DEFAULT NULL,
    INOUT o_effective_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_profile app.user_profile%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_profile FROM app.user_profile WHERE user_id = p_user_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR v_profile.onboarding_completed_at IS NULL THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;

    UPDATE app.user_profile AS p
    SET full_name = coalesce(p_full_name, p.full_name),
        biological_sex = coalesce(p_biological_sex, p.biological_sex),
        avatar_code = coalesce(p_avatar_code, p.avatar_code),
        age_years = coalesce(p_age_years, p.age_years),
        age_recorded_on = CASE WHEN p_age_years IS NULL THEN p.age_recorded_on ELSE common.fn_local_date(p.timezone) END,
        height_cm = coalesce(p_height_cm, p.height_cm),
        weight_kg = coalesce(p_weight_kg, p.weight_kg),
        target_weight_kg = coalesce(p_target_weight_kg, p.target_weight_kg),
        weight_goal_code = coalesce(p_weight_goal_code, p.weight_goal_code),
        activity_level_code = coalesce(p_activity_level_code, p.activity_level_code),
        body_type_code = coalesce(p_body_type_code, p.body_type_code),
        medical_conditions = coalesce(p_medical_conditions, p.medical_conditions)
    WHERE p.user_id = p_user_id;

    IF p_snapshot IS NOT NULL THEN
        o_effective_date := common.fn_local_date(v_profile.timezone);
        CALL app.pr_upsert_target_snapshot(p_user_id, o_effective_date, p_snapshot);
        -- Today's nutrition summary keeps the calorie target it copied at its last refresh (a meal or
        -- workout write), so without this a profile edit changed nothing on Home until the next meal
        -- (owner 2026-11-24). Re-read the new target now; days before today are never touched.
        IF EXISTS (
            SELECT 1 FROM nutrition.daily_summary AS d
            WHERE d.user_id = p_user_id AND d.local_date = o_effective_date
            FOR UPDATE
        ) THEN
            CALL nutrition.pr_refresh_daily_summary(p_user_id, o_effective_date);
        END IF;
    ELSE
        o_effective_date := NULL;
    END IF;
END
$$;

COMMENT ON PROCEDURE app.pr_update_profile (
    uuid, common.safe_text, common.code, common.code, smallint, numeric, numeric, numeric, common.code,
    common.code, common.code, common.code[], jsonb, date
) IS 'Partial profile update; optional snapshot replaces today''s targets only';
REVOKE ALL ON PROCEDURE app.pr_update_profile(
    uuid, common.safe_text, common.code, common.code, smallint, numeric, numeric, numeric, common.code,
    common.code, common.code, common.code[], jsonb, date
) FROM public;
GRANT EXECUTE ON PROCEDURE app.pr_update_profile(
    uuid, common.safe_text, common.code, common.code, smallint, numeric, numeric, numeric, common.code,
    common.code, common.code, common.code[], jsonb, date
) TO app_rw;
