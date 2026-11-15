-- PUT /me/onboarding/steps/{step} (doc 04 section 2.2). Saves one onboarding screen; the profile row
-- is created on the first save. Steps can be revisited but not skipped (step <= saved step + 1).
-- Each step must carry its own fields (other parameters are ignored for that step):
--   1 biological_sex, avatar_code, full_name   2 height_cm   3 weight_kg, weight_goal_code
--   4 target_weight_kg, medical_conditions (optional)   5 age_years, activity_level_code
--   6 body_type_code
-- Ranges and codes are enforced by the table CHECKs and FKs (23514 / 23503).
-- Errors: 22023 ONBOARDING_STEP_INVALID / ONBOARDING_STEP_OUT_OF_ORDER / ONBOARDING_FIELDS_MISSING,
--         P0001 ONBOARDING_ALREADY_COMPLETED (later edits go through app.pr_update_profile).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_save_onboarding_step(
    p_user_id uuid,
    p_step smallint,
    p_biological_sex common.code DEFAULT NULL,
    p_avatar_code common.code DEFAULT NULL,
    p_full_name common.safe_text DEFAULT NULL,
    p_height_cm numeric DEFAULT NULL,
    p_weight_kg numeric DEFAULT NULL,
    p_weight_goal_code common.code DEFAULT NULL,
    p_target_weight_kg numeric DEFAULT NULL,
    p_medical_conditions common.code[] DEFAULT NULL,
    p_age_years smallint DEFAULT NULL,
    p_activity_level_code common.code DEFAULT NULL,
    p_body_type_code common.code DEFAULT NULL,
    INOUT o_current_step smallint DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_profile app.user_profile%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_step IS NULL OR p_step NOT BETWEEN 1 AND 6 THEN
        RAISE EXCEPTION 'step must be 1..6' USING ERRCODE = '22023', DETAIL = 'ONBOARDING_STEP_INVALID';
    END IF;

    INSERT INTO app.user_profile (user_id) VALUES (p_user_id) ON CONFLICT (user_id) DO NOTHING;
    SELECT * INTO v_profile FROM app.user_profile WHERE user_id = p_user_id FOR UPDATE;

    IF v_profile.onboarding_completed_at IS NOT NULL THEN
        RAISE EXCEPTION 'onboarding already completed' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_ALREADY_COMPLETED';
    END IF;
    IF p_step > v_profile.onboarding_step + 1 THEN
        RAISE EXCEPTION 'complete the previous step first' USING ERRCODE = '22023', DETAIL = 'ONBOARDING_STEP_OUT_OF_ORDER';
    END IF;
    IF (p_step = 1 AND (p_biological_sex IS NULL OR p_avatar_code IS NULL OR p_full_name IS NULL))
       OR (p_step = 2 AND p_height_cm IS NULL)
       OR (p_step = 3 AND (p_weight_kg IS NULL OR p_weight_goal_code IS NULL))
       OR (p_step = 4 AND p_target_weight_kg IS NULL)
       OR (p_step = 5 AND (p_age_years IS NULL OR p_activity_level_code IS NULL))
       OR (p_step = 6 AND p_body_type_code IS NULL) THEN
        RAISE EXCEPTION 'required fields for this step are missing'
            USING ERRCODE = '22023', DETAIL = 'ONBOARDING_FIELDS_MISSING';
    END IF;

    UPDATE app.user_profile AS p
    SET biological_sex = CASE WHEN p_step = 1 THEN p_biological_sex ELSE p.biological_sex END,
        avatar_code = CASE WHEN p_step = 1 THEN p_avatar_code ELSE p.avatar_code END,
        full_name = CASE WHEN p_step = 1 THEN p_full_name ELSE p.full_name END,
        height_cm = CASE WHEN p_step = 2 THEN p_height_cm ELSE p.height_cm END,
        weight_kg = CASE WHEN p_step = 3 THEN p_weight_kg ELSE p.weight_kg END,
        weight_goal_code = CASE WHEN p_step = 3 THEN p_weight_goal_code ELSE p.weight_goal_code END,
        target_weight_kg = CASE WHEN p_step = 4 THEN p_target_weight_kg ELSE p.target_weight_kg END,
        medical_conditions = CASE WHEN p_step = 4 THEN p_medical_conditions ELSE p.medical_conditions END,
        age_years = CASE WHEN p_step = 5 THEN p_age_years ELSE p.age_years END,
        age_recorded_on = CASE WHEN p_step = 5 THEN common.fn_local_date(p.timezone) ELSE p.age_recorded_on END,
        activity_level_code = CASE WHEN p_step = 5 THEN p_activity_level_code ELSE p.activity_level_code END,
        body_type_code = CASE WHEN p_step = 6 THEN p_body_type_code ELSE p.body_type_code END,
        onboarding_step = greatest(p.onboarding_step, p_step)
    WHERE p.user_id = p_user_id
    RETURNING p.onboarding_step INTO o_current_step;
END
$$;

COMMENT ON PROCEDURE app.pr_save_onboarding_step (
    uuid, smallint, common.code, common.code, common.safe_text, numeric, numeric, common.code, numeric,
    common.code[], smallint, common.code, common.code, smallint
) IS 'Save one onboarding step (1..6) in order; creates the profile on first save';
REVOKE ALL ON PROCEDURE app.pr_save_onboarding_step(
    uuid, smallint, common.code, common.code, common.safe_text, numeric, numeric, common.code, numeric,
    common.code[], smallint, common.code, common.code, smallint
) FROM public;
GRANT EXECUTE ON PROCEDURE app.pr_save_onboarding_step(
    uuid, smallint, common.code, common.code, common.safe_text, numeric, numeric, common.code, numeric,
    common.code[], smallint, common.code, common.code, smallint
) TO app_rw;
