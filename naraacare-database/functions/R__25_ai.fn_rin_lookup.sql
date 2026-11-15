-- Rin data on demand (owner 2026-11-08): when the context block (today + last 7 days) is not
-- enough, the model calls its get_my_data tool and the API answers from here. Same gate and the
-- same data minimisation as fn_rin_context: the caller's own aggregates only, numbers and catalogue
-- food names (never free text, names, email or anyone else), at most the last 90 days.
--   * kind 'day': water, food and sleep totals of one local date.
--   * kind 'period': averages and goal days over the last p_days (1..90) up to today.
--   * kind 'meals': the meals of one local date: type, time and items (catalogue name, kcal, protein).
-- Errors: P0001 ONBOARDING_INCOMPLETE / UPGRADE_REQUIRED / CONSENT_REQUIRED (fn_require_rin),
--         22023 INVALID_ARGUMENT (unknown kind, date outside the last 90 days, days outside 1..90).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION ai.fn_rin_lookup(
    p_user_id uuid, p_kind text, p_date date DEFAULT NULL, p_days integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_tz common.iana_timezone;
    v_today date;
    v_from date;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_tz := ai.fn_require_rin(p_user_id);
    v_today := common.fn_local_date(v_tz);

    IF p_kind IN ('day', 'meals') THEN
        IF p_date IS NULL OR p_date > v_today OR p_date < v_today - 90 THEN
            RAISE EXCEPTION 'date must be within the last 90 days' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
        END IF;
    ELSIF p_kind = 'period' THEN
        IF p_days IS NULL OR p_days NOT BETWEEN 1 AND 90 THEN
            RAISE EXCEPTION 'days must be 1 to 90' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
        END IF;
        v_from := v_today - (p_days - 1);
    ELSE
        RAISE EXCEPTION 'unknown kind' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;

    IF p_kind = 'day' THEN
        RETURN jsonb_strip_nulls(jsonb_build_object(
            'date', p_date,
            'water', (
                SELECT jsonb_build_object(
                    'consumed_ml', round(h.effective_intake_ml)::integer, 'goal_ml', h.daily_need_ml,
                    'goal_completed', h.goal_completed_at IS NOT NULL
                )
                FROM hydration.daily_summary AS h WHERE h.user_id = p_user_id AND h.local_date = p_date
            ),
            'food', (
                SELECT jsonb_build_object(
                    'kcal', round(n.calories_kcal_total)::integer, 'allowance_kcal', n.effective_allowance_kcal,
                    'protein_g', round(n.protein_g_total)::integer, 'carbs_g', round(n.carbohydrates_g_total)::integer,
                    'fat_g', round(n.fat_g_total)::integer, 'fiber_g', round(n.dietary_fiber_g_total)::integer,
                    'sugar_g', round(n.total_sugar_g_total)::integer, 'sodium_mg', round(n.sodium_mg_total)::integer,
                    'meals', n.meal_count
                )
                FROM nutrition.daily_summary AS n WHERE n.user_id = p_user_id AND n.local_date = p_date
            ),
            'sleep', (
                SELECT jsonb_build_object('counted_min', s.counted_min, 'goal_min', s.goal_min, 'score_pct', s.score_pct)
                FROM sleep.daily_summary AS s WHERE s.user_id = p_user_id AND s.local_date = p_date
            )
        ));
    ELSIF p_kind = 'period' THEN
        RETURN jsonb_strip_nulls(jsonb_build_object(
            'from', v_from, 'to', v_today, 'days', p_days,
            'water', (
                SELECT jsonb_build_object(
                    'days_logged', count(*) FILTER (WHERE h.volume_ml > 0),
                    'avg_ml', round(avg(h.effective_intake_ml) FILTER (WHERE h.volume_ml > 0))::integer,
                    'goal_days', count(*) FILTER (WHERE h.goal_completed_at IS NOT NULL)
                )
                FROM hydration.daily_summary AS h
                WHERE h.user_id = p_user_id AND h.local_date BETWEEN v_from AND v_today
            ),
            'food', (
                SELECT jsonb_build_object(
                    'days_logged', count(*),
                    'avg_kcal', round(avg(n.calories_kcal_total))::integer,
                    'avg_allowance_kcal', round(avg(n.effective_allowance_kcal))::integer,
                    'avg_protein_g', round(avg(n.protein_g_total))::integer,
                    'avg_carbs_g', round(avg(n.carbohydrates_g_total))::integer,
                    'avg_fat_g', round(avg(n.fat_g_total))::integer,
                    'avg_fiber_g', round(avg(n.dietary_fiber_g_total))::integer
                )
                FROM nutrition.daily_summary AS n
                WHERE n.user_id = p_user_id AND n.local_date BETWEEN v_from AND v_today AND n.meal_count > 0
            ),
            'sleep', (
                SELECT jsonb_build_object(
                    'nights_logged', count(*),
                    'avg_min', round(avg(s.counted_min))::integer,
                    'avg_score_pct', round(avg(s.score_pct))::integer,
                    'goal_nights', count(*) FILTER (WHERE s.counted_min >= s.goal_min)
                )
                FROM sleep.daily_summary AS s
                WHERE s.user_id = p_user_id AND s.local_date BETWEEN v_from AND v_today AND s.counted_min > 0
            )
        ));
    END IF;
    RETURN jsonb_build_object(
        'date', p_date,
        'meals', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                'meal_type', m.meal_type,
                'time', to_char(m.logged_at AT TIME ZONE v_tz, 'HH24:MI'),
                'items', (
                    SELECT coalesce(jsonb_agg(jsonb_build_object(
                        'food', f.name,
                        'kcal', round(i.calories_kcal)::integer,
                        'protein_g', round(i.protein_g, 1)
                    ) ORDER BY i.id), '[]'::jsonb)
                    FROM nutrition.meal_item AS i
                    INNER JOIN nutrition.food_item AS f ON f.id = i.food_id
                    WHERE i.meal_id = m.id AND i.meal_logged_at = m.logged_at AND i.deleted_at IS NULL
                )
            ) ORDER BY m.logged_at)
            FROM nutrition.meal AS m
            WHERE m.user_id = p_user_id AND m.local_date = p_date AND m.deleted_at IS NULL
        ), '[]'::jsonb)
    );
END
$$;

COMMENT ON FUNCTION ai.fn_rin_lookup(uuid, text, date, integer) IS
'Rin tool get_my_data: own day totals, period averages or a day''s meals (last 90 days, numbers and catalogue names)';
REVOKE ALL ON FUNCTION ai.fn_rin_lookup(uuid, text, date, integer) FROM public;
GRANT EXECUTE ON FUNCTION ai.fn_rin_lookup(uuid, text, date, integer) TO app_rw;
