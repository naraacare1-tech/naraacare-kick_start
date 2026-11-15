-- GET /hydration/status (doc 04 section 2.5, doc 06 section 3): everything the status engine needs
-- for one local day (p_date NULL = today in the user's timezone), in one round trip. The engine itself (drain integration, tank, bands, states)
-- is a pure function in the API (app/domain/hydration/status.py), unit-tested against doc 06.
--   profile:   the target snapshot in force that day (sex, age, height, weight, body type, activity),
--              its calc_version and base need, plus timezone and the wake / sleep times.
--   advanced:  the advanced_hydration feature (OQ-04). STANDARD ignores temperatures and workouts
--              (kept after a downgrade, hidden, doc 06 section 9), so they are still returned.
--   temperatures, intakes, workouts, meal_credits (logged_at of the meals with a food credit):
--              non-deleted rows of that local date in time order.
-- Errors: 42501 not the actor (-> 404), P0001 ONBOARDING_INCOMPLETE (no profile or snapshot yet).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION hydration.fn_day_inputs(p_user_id uuid, p_date date)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_profile app.user_profile%ROWTYPE;
    v_snapshot app.health_target_snapshot%ROWTYPE;
    v_features jsonb;
    v_tier text;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_profile FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    p_date := coalesce(p_date, common.fn_local_date(v_profile.timezone));
    SELECT * INTO v_snapshot FROM app.health_target_snapshot AS s
    WHERE s.user_id = p_user_id AND s.effective_date <= p_date
    ORDER BY s.effective_date DESC
    LIMIT 1;
    IF NOT FOUND THEN
        -- A day before the first snapshot (backdating): use the first one.
        SELECT * INTO v_snapshot FROM app.health_target_snapshot AS s
        WHERE s.user_id = p_user_id
        ORDER BY s.effective_date
        LIMIT 1;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
        END IF;
    END IF;
    SELECT e.features, e.tier_code INTO v_features, v_tier FROM billing.fn_current_entitlement(p_user_id) AS e;

    RETURN jsonb_build_object(
        'date', p_date,
        'today', common.fn_local_date(v_profile.timezone),
        'timezone', v_profile.timezone,
        'wake_local', to_char(v_profile.wake_local, 'HH24:MI'),
        'sleep_start_local', to_char(v_profile.sleep_start_local, 'HH24:MI'),
        'temperature_unit', v_profile.temperature_unit,
        'tier', v_tier,
        'advanced', coalesce((v_features ->> 'advanced_hydration')::boolean, FALSE),
        'calc_version', v_snapshot.calc_version,
        'inputs', v_snapshot.inputs,
        'base_water_need_ml', v_snapshot.base_water_need_ml,
        'temperatures', coalesce((
            SELECT jsonb_agg(jsonb_build_object('c', t.temperature_c, 'from', t.effective_from)
                ORDER BY t.effective_from, t.id)
            FROM hydration.temperature_log AS t
            WHERE t.user_id = p_user_id AND t.local_date = p_date
        ), '[]'::jsonb),
        'intakes', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                'at', i.logged_at, 'drink_code', i.drink_code, 'volume_ml', i.volume_ml,
                'effective_ml', i.effective_ml
            ) ORDER BY i.logged_at, i.id)
            FROM hydration.intake AS i
            WHERE i.user_id = p_user_id AND i.local_date = p_date AND i.deleted_at IS NULL
        ), '[]'::jsonb),
        'workouts', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                'at', w.performed_at, 'workout_type', w.workout_type, 'duration_min', w.duration_min,
                'sweat_ml', w.sweat_ml, 'kcal', w.kcal
            ) ORDER BY w.performed_at, w.id)
            FROM activity.workout AS w
            WHERE w.user_id = p_user_id AND w.local_date = p_date AND w.deleted_at IS NULL
        ), '[]'::jsonb),
        'meal_credits', coalesce((
            SELECT jsonb_agg(m.logged_at ORDER BY m.logged_at)
            FROM nutrition.meal AS m
            WHERE
                m.user_id = p_user_id AND m.local_date = p_date AND m.deleted_at IS NULL
                AND m.hydration_credit
        ), '[]'::jsonb),
        'goal_completed_at', (
            SELECT d.goal_completed_at FROM hydration.daily_summary AS d
            WHERE d.user_id = p_user_id AND d.local_date = p_date
        )
    );
END
$$;

COMMENT ON FUNCTION hydration.fn_day_inputs(uuid, date) IS
'Inputs of the hydration status engine for one local day (profile snapshot, tier, logs, credits)';
REVOKE ALL ON FUNCTION hydration.fn_day_inputs(uuid, date) FROM public;
GRANT EXECUTE ON FUNCTION hydration.fn_day_inputs(uuid, date) TO app_rw;
