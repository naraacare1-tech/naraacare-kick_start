-- GET /nutrition/daily-summary (doc 04 section 2.4, doc 06 sections 2.7-2.8): one row for a local
-- day, also when nothing was logged yet (zeros). Targets come from the snapshot in force that day
-- (past days keep their targets); the meal limit from the current entitlement. The API computes the
-- avatar fill/state from calories_total and effective_allowance_kcal and filters nutrients by tier.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_daily_summary(p_user_id uuid, p_date date DEFAULT NULL)
RETURNS TABLE (
    local_date date,
    totals jsonb,
    meal_count integer,
    meal_limit integer,
    exercise_kcal integer,
    base_target_kcal integer,
    effective_allowance_kcal integer,
    calc_version text,
    last_updated timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_date date := p_date;
    v_target integer;
    v_calc text;
    v_limit integer;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF v_date IS NULL THEN
        SELECT common.fn_local_date(p.timezone) INTO v_date FROM app.user_profile AS p WHERE p.user_id = p_user_id;
        v_date := coalesce(v_date, common.fn_local_date(NULL));
    END IF;
    SELECT s.base_target_kcal, s.calc_version INTO v_target, v_calc
    FROM app.fn_latest_target_snapshot(p_user_id, v_date) AS s;
    SELECT (e.limits ->> 'meal_logs_per_day')::integer INTO v_limit
    FROM billing.fn_current_entitlement(p_user_id) AS e;

    RETURN QUERY
    SELECT
        v_date,
        jsonb_build_object(
            'calories', coalesce(d.calories_kcal_total, 0), 'protein', coalesce(d.protein_g_total, 0),
            'carbohydrates', coalesce(d.carbohydrates_g_total, 0), 'fat', coalesce(d.fat_g_total, 0),
            'dietary_fiber', coalesce(d.dietary_fiber_g_total, 0),
            'total_sugar', coalesce(d.total_sugar_g_total, 0),
            'saturated_fat', coalesce(d.saturated_fat_g_total, 0),
            'polyunsaturated_fat', coalesce(d.polyunsaturated_fat_g_total, 0),
            'monounsaturated_fat', coalesce(d.monounsaturated_fat_g_total, 0),
            'trans_fat', coalesce(d.trans_fat_g_total, 0),
            'cholesterol', coalesce(d.cholesterol_mg_total, 0), 'sodium', coalesce(d.sodium_mg_total, 0),
            'potassium', coalesce(d.potassium_mg_total, 0), 'calcium', coalesce(d.calcium_mg_total, 0),
            'iron', coalesce(d.iron_mg_total, 0), 'vitamin_a', coalesce(d.vitamin_a_mcg_total, 0),
            'vitamin_c', coalesce(d.vitamin_c_mg_total, 0)
        ),
        coalesce(d.meal_count, 0)::integer,
        coalesce(v_limit, 4),
        coalesce(d.exercise_kcal, 0),
        coalesce(d.base_target_kcal, v_target),
        coalesce(d.base_target_kcal, v_target) + coalesce(d.exercise_kcal, 0),
        coalesce(d.calc_version::text, v_calc),
        d.updated_at
    FROM (SELECT 1) AS one
    LEFT JOIN nutrition.daily_summary AS d ON d.user_id = p_user_id AND d.local_date = v_date;
END
$$;

COMMENT ON FUNCTION nutrition.fn_daily_summary(uuid, date) IS
'Daily nutrition totals (17), meal count/limit, targets and allowance for one local day';
REVOKE ALL ON FUNCTION nutrition.fn_daily_summary(uuid, date) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_daily_summary(uuid, date) TO app_rw, app_readonly;
