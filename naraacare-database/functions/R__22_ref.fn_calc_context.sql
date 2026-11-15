-- Everything the API's domain calculators need (doc 06), in one call: the calc_version in force,
-- its constants (ref.calc_constant) and the reference rows that carry numbers (activity multipliers
-- and hydration activity numbers, body-type factors, goal deltas, BMI categories with blocked goals,
-- medical condition codes). The API caches it for a few minutes; snapshots record calc_version, so
-- past days stay reproducible when constants change.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION ref.fn_calc_context()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_version text;
BEGIN
    SELECT max(v.code) INTO v_version FROM ref.calc_version AS v WHERE v.effective_from <= current_date;
    RETURN jsonb_build_object(
        'calc_version', v_version,
        'constants', (
            SELECT coalesce(jsonb_object_agg(c.key, c.value), '{}')
            FROM ref.calc_constant AS c
            WHERE c.calc_version = v_version
        ),
        'activity_levels', (
            SELECT coalesce(jsonb_object_agg(a.code, jsonb_build_object(
                'tdee_multiplier', a.tdee_multiplier,
                'activity_number', h.activity_number,
                'athlete_bonus_ml', h.athlete_bonus_ml
            )), '{}')
            FROM ref.activity_level AS a
            INNER JOIN ref.hydration_activity AS h ON h.code = a.hydration_activity_code
        ),
        'body_types', (
            SELECT coalesce(jsonb_object_agg(b.code, b.lbw_factor), '{}') FROM ref.body_type AS b
        ),
        'weight_goals', (
            SELECT coalesce(jsonb_object_agg(g.code, jsonb_build_object(
                'kcal_delta', g.kcal_delta, 'direction', g.direction, 'display_order', g.display_order,
                'offered', g.offered
            )), '{}')
            FROM ref.weight_goal AS g
        ),
        'bmi_categories', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', b.code, 'min_bmi', b.min_bmi, 'max_bmi_exclusive', b.max_bmi_exclusive,
                'blocked_goal_codes', to_jsonb(b.blocked_goal_codes)
            ) ORDER BY b.min_bmi), '[]')
            FROM ref.bmi_category AS b
        ),
        'medical_condition_codes', (
            SELECT coalesce(jsonb_agg(m.code ORDER BY m.code), '[]') FROM ref.medical_condition AS m
        ),
        'avatar_codes', (
            SELECT coalesce(jsonb_agg(v.code ORDER BY v.code), '[]') FROM ref.avatar AS v
        )
    );
END
$$;

COMMENT ON FUNCTION ref.fn_calc_context() IS
'Calc version in force, its constants and the numeric reference rows the API calculators use';
REVOKE ALL ON FUNCTION ref.fn_calc_context() FROM public;
GRANT EXECUTE ON FUNCTION ref.fn_calc_context() TO app_rw, app_worker, app_readonly;
