-- Internal: writes the user's targets for one day (doc 06 section 1). The calculations run in the API
-- (domain calculators, constants from ref.calc_constant) and arrive as a JSON object whose keys are the
-- snapshot columns: calc_version, inputs, bmi, bmi_category, bmr_kcal, tdee_kcal, goal_delta_kcal,
-- calculated_target_kcal, base_target_kcal, safety_override, carbs_g, fat_g, protein_g,
-- lean_body_weight_kg, water_movement_ml, base_water_need_ml. Unknown keys raise 22023; missing or
-- out-of-range values hit the table's NOT NULL / CHECK constraints. An existing snapshot for the same
-- day is replaced; other days are never touched ("past days unchanged").
-- Not granted to app_rw: only reachable through app.pr_complete_onboarding and app.pr_update_profile.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_upsert_target_snapshot(
    p_user_id uuid,
    p_effective_date date,
    p_snapshot jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v app.health_target_snapshot;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_snapshot IS NULL OR jsonb_typeof(p_snapshot) <> 'object' OR p_effective_date IS NULL THEN
        RAISE EXCEPTION 'snapshot must be a JSON object' USING ERRCODE = '22023', DETAIL = 'INVALID_SNAPSHOT';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_object_keys(p_snapshot) AS k
        WHERE k NOT IN (
            'calc_version', 'inputs', 'bmi', 'bmi_category', 'bmr_kcal', 'tdee_kcal', 'goal_delta_kcal',
            'calculated_target_kcal', 'base_target_kcal', 'safety_override', 'carbs_g', 'fat_g', 'protein_g',
            'lean_body_weight_kg', 'water_movement_ml', 'base_water_need_ml'
        )
    ) THEN
        RAISE EXCEPTION 'unknown snapshot field' USING ERRCODE = '22023', DETAIL = 'INVALID_SNAPSHOT';
    END IF;

    v := jsonb_populate_record(NULL::app.health_target_snapshot, p_snapshot);

    INSERT INTO app.health_target_snapshot (
        user_id, effective_date, calc_version, inputs, bmi, bmi_category, bmr_kcal, tdee_kcal,
        goal_delta_kcal, calculated_target_kcal, base_target_kcal, safety_override, carbs_g, fat_g,
        protein_g, lean_body_weight_kg, water_movement_ml, base_water_need_ml
    ) VALUES (
        p_user_id, p_effective_date, v.calc_version, v.inputs, v.bmi, v.bmi_category, v.bmr_kcal, v.tdee_kcal,
        v.goal_delta_kcal, v.calculated_target_kcal, v.base_target_kcal, v.safety_override, v.carbs_g, v.fat_g,
        v.protein_g, v.lean_body_weight_kg, v.water_movement_ml, v.base_water_need_ml
    )
    ON CONFLICT (user_id, effective_date) DO UPDATE SET
        calc_version = excluded.calc_version,
        inputs = excluded.inputs,
        bmi = excluded.bmi,
        bmi_category = excluded.bmi_category,
        bmr_kcal = excluded.bmr_kcal,
        tdee_kcal = excluded.tdee_kcal,
        goal_delta_kcal = excluded.goal_delta_kcal,
        calculated_target_kcal = excluded.calculated_target_kcal,
        base_target_kcal = excluded.base_target_kcal,
        safety_override = excluded.safety_override,
        carbs_g = excluded.carbs_g,
        fat_g = excluded.fat_g,
        protein_g = excluded.protein_g,
        lean_body_weight_kg = excluded.lean_body_weight_kg,
        water_movement_ml = excluded.water_movement_ml,
        base_water_need_ml = excluded.base_water_need_ml,
        created_at = now();
EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range OR datatype_mismatch THEN
    RAISE EXCEPTION 'snapshot field has the wrong type' USING ERRCODE = '22023', DETAIL = 'INVALID_SNAPSHOT';
END
$$;

COMMENT ON PROCEDURE app.pr_upsert_target_snapshot (uuid, date, jsonb) IS
'Internal: replace one day''s target snapshot from API-computed values (other days untouched)';
REVOKE ALL ON PROCEDURE app.pr_upsert_target_snapshot(uuid, date, jsonb) FROM public;
