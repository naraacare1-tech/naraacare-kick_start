-- POST /workouts and DELETE /workouts/{id} (doc 04 section 2.5, doc 06 sections 2.7 and 3.4, OQ-58).
-- STAR only (advanced_hydration, OQ-04). Several workouts a day add up.
--   * Snapshots at write time (weight from the target snapshot in force that day, rates from
--     ref.workout_type): sweat_ml = sweat rate x kg x min / 60 (1 decimal),
--     kcal = MET x kg x hours, rounded half-up (OQ-16 proposal).
--   * Same transaction: nutrition.daily_summary.exercise_kcal (effective allowance = base target +
--     exercise, doc 06 section 2.7) and hydration.daily_summary.workout_sweat_ml are rebuilt, under
--     the two summary row locks (nutrition first, then hydration, in every procedure).
--   * Idempotent by client id (o_status 'duplicate'); 7-day backdating; +5 min future tolerance.
--   * Delete: If-Match version, last 2 workouts within 7 days.
-- Errors: 42501 not the actor / not found, 22023 invalid, P0001 UPGRADE_REQUIRED / EDIT_WINDOW_CLOSED /
--         VERSION_CONFLICT / ONBOARDING_INCOMPLETE.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal: rebuild exercise kcal (nutrition) and sweat (hydration) for one day, both rows locked.
CREATE OR REPLACE PROCEDURE activity.pr_refresh_workout_totals(p_user_id uuid, p_date date)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    INSERT INTO nutrition.daily_summary (user_id, local_date)
    VALUES (p_user_id, p_date)
    ON CONFLICT (user_id, local_date) DO NOTHING;
    PERFORM 1 FROM nutrition.daily_summary AS d
    WHERE d.user_id = p_user_id AND d.local_date = p_date FOR UPDATE;
    CALL hydration.pr_lock_daily_summary(p_user_id, p_date);

    UPDATE nutrition.daily_summary AS d
    SET exercise_kcal = (
        SELECT coalesce(sum(w.kcal), 0) FROM activity.workout AS w
        WHERE w.user_id = p_user_id AND w.local_date = p_date AND w.deleted_at IS NULL
    )
    WHERE d.user_id = p_user_id AND d.local_date = p_date;
    -- Recomputes the allowance (base target + exercise) and keeps the meal totals consistent.
    CALL nutrition.pr_refresh_daily_summary(p_user_id, p_date);
    CALL hydration.pr_refresh_daily_summary(p_user_id, p_date);
END
$$;

COMMENT ON PROCEDURE activity.pr_refresh_workout_totals (uuid, date) IS
'Internal: rebuild a day''s exercise kcal (nutrition allowance) and workout sweat (hydration)';
REVOKE ALL ON PROCEDURE activity.pr_refresh_workout_totals(uuid, date) FROM public;

CREATE OR REPLACE PROCEDURE activity.pr_log_workout(
    p_user_id uuid,
    p_workout_id uuid,
    p_performed_at timestamptz,
    p_workout_type common.code,
    p_duration_min integer,
    INOUT o_status text DEFAULT NULL,
    INOUT o_local_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_features jsonb;
    v_weight numeric;
    v_calc common.version_label;
    v_type ref.workout_type%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_workout_id IS NULL OR p_performed_at IS NULL OR p_workout_type IS NULL OR p_duration_min IS NULL THEN
        RAISE EXCEPTION 'workout id, time, type and duration are required'
            USING ERRCODE = '22023', DETAIL = 'WORKOUT_INVALID';
    END IF;
    IF p_duration_min NOT BETWEEN 1 AND 600 THEN
        RAISE EXCEPTION 'duration must be 1..600 minutes' USING ERRCODE = '22023', DETAIL = 'DURATION_INVALID';
    END IF;

    SELECT w.local_date INTO o_local_date
    FROM activity.workout AS w WHERE w.id = p_workout_id AND w.user_id = p_user_id;
    IF FOUND THEN
        o_status := 'duplicate';
        RETURN;
    END IF;

    SELECT p.timezone INTO v_timezone
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF NOT coalesce((v_features ->> 'advanced_hydration')::boolean, FALSE) THEN
        RAISE EXCEPTION 'workouts need STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;
    SELECT * INTO v_type FROM ref.workout_type AS t WHERE t.code = p_workout_type;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'unknown workout type' USING ERRCODE = '22023', DETAIL = 'WORKOUT_INVALID';
    END IF;
    IF p_performed_at > now() + interval '5 minutes' THEN
        RAISE EXCEPTION 'performed_at is in the future' USING ERRCODE = '22023', DETAIL = 'LOGGED_AT_INVALID';
    END IF;
    o_local_date := common.fn_local_date(v_timezone, p_performed_at);
    IF o_local_date < common.fn_local_date(v_timezone) - 7 THEN
        RAISE EXCEPTION 'entries older than 7 days cannot be added'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    SELECT (s.inputs ->> 'weight_kg')::numeric, s.calc_version INTO v_weight, v_calc
    FROM app.health_target_snapshot AS s
    WHERE s.user_id = p_user_id
    ORDER BY (s.effective_date <= o_local_date) DESC,
             CASE WHEN s.effective_date <= o_local_date THEN s.effective_date END DESC,
             s.effective_date
    LIMIT 1;
    IF v_weight IS NULL THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;

    INSERT INTO activity.workout (
        id, performed_at, user_id, local_date, workout_type, duration_min, sweat_ml, kcal, calc_version,
        created_by, updated_by
    )
    VALUES (
        p_workout_id, p_performed_at, p_user_id, o_local_date, p_workout_type, p_duration_min,
        round(v_type.sweat_ml_per_kg_h * v_weight * p_duration_min / 60.0, 1),
        round(v_type.met * v_weight * p_duration_min / 60.0)::integer,
        v_calc, p_user_id, p_user_id
    );

    CALL activity.pr_refresh_workout_totals(p_user_id, o_local_date);

    INSERT INTO app.user_activity_day (user_id, local_date, has_hydration)
    VALUES (p_user_id, o_local_date, TRUE)
    ON CONFLICT (user_id, local_date) DO UPDATE SET has_hydration = TRUE;

    o_status := 'created';
END
$$;

COMMENT ON PROCEDURE activity.pr_log_workout (uuid, uuid, timestamptz, common.code, integer, text, date) IS
'STAR: save a workout (idempotent by client id) with sweat/kcal snapshots; allowance and sweat rebuilt';
REVOKE ALL ON PROCEDURE activity.pr_log_workout(uuid, uuid, timestamptz, common.code, integer, text, date) FROM public;
GRANT EXECUTE ON PROCEDURE activity.pr_log_workout(uuid, uuid, timestamptz, common.code, integer, text, date) TO app_rw;

CREATE OR REPLACE PROCEDURE activity.pr_delete_workout(
    p_user_id uuid,
    p_workout_id uuid,
    p_expected_version integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row activity.workout%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_row FROM activity.workout AS w
    WHERE w.id = p_workout_id AND w.user_id = p_user_id AND w.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'workout not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;
    PERFORM 1 FROM activity.workout AS w
    WHERE w.id = p_workout_id AND w.performed_at = v_row.performed_at FOR UPDATE;
    IF p_expected_version IS DISTINCT FROM v_row.version THEN
        RAISE EXCEPTION 'workout was changed elsewhere' USING ERRCODE = 'P0001', DETAIL = 'VERSION_CONFLICT';
    END IF;
    IF p_workout_id NOT IN (SELECT e FROM activity.fn_editable_workout_ids(p_user_id) AS e) THEN
        RAISE EXCEPTION 'only the last 2 workouts within 7 days can be deleted'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    UPDATE activity.workout AS w
    SET deleted_at = now(), version = w.version + 1, updated_by = p_user_id, updated_at = now()
    WHERE w.id = p_workout_id AND w.performed_at = v_row.performed_at;
    CALL activity.pr_refresh_workout_totals(p_user_id, v_row.local_date);
END
$$;

COMMENT ON PROCEDURE activity.pr_delete_workout (uuid, uuid, integer) IS
'STAR: soft-delete one of the last 2 workouts (If-Match version); allowance and sweat rebuilt';
REVOKE ALL ON PROCEDURE activity.pr_delete_workout(uuid, uuid, integer) FROM public;
GRANT EXECUTE ON PROCEDURE activity.pr_delete_workout(uuid, uuid, integer) TO app_rw;
