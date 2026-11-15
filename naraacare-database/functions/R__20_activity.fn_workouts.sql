-- GET /workouts?date= and the workout representation for 201/409 responses (doc 04 section 2.5).
-- Workouts of one local day in time order with the snapshot sweat and kcal and the delete flag
-- (last 2 within 7 days); with p_workout_id, that one workout whatever its day.
-- Errors: 42501 not the actor (-> 404).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION activity.fn_workouts(p_user_id uuid, p_date date, p_workout_id uuid DEFAULT NULL)
RETURNS TABLE (
    workout_id uuid,
    performed_at timestamptz,
    local_date date,
    workout_type common.code,
    label text,
    duration_min smallint,
    sweat_ml numeric,
    kcal integer,
    version integer,
    editable boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    WITH editable AS (SELECT e AS id FROM activity.fn_editable_workout_ids(p_user_id) AS e)
    SELECT
        w.id, w.performed_at, w.local_date, w.workout_type, t.label::text, w.duration_min, w.sweat_ml,
        w.kcal, w.version, w.id IN (SELECT e.id FROM editable AS e)
    FROM activity.workout AS w
    INNER JOIN ref.workout_type AS t ON t.code = w.workout_type
    WHERE
        w.user_id = p_user_id AND w.deleted_at IS NULL
        AND (CASE WHEN p_workout_id IS NULL THEN w.local_date = p_date ELSE w.id = p_workout_id END)
    ORDER BY w.performed_at, w.id;
END
$$;

COMMENT ON FUNCTION activity.fn_workouts(uuid, date, uuid) IS
'Workouts of a local day (or one by id) with sweat, kcal and the delete flag';
REVOKE ALL ON FUNCTION activity.fn_workouts(uuid, date, uuid) FROM public;
GRANT EXECUTE ON FUNCTION activity.fn_workouts(uuid, date, uuid) TO app_rw;
