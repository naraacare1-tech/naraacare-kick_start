-- GET /sync/changes (Session 14, doc 04 section 2.14, doc 03 section 3.1). The caller's meals, drink
-- intakes, workouts and sleep entries changed after a cursor, oldest change first, including
-- soft-deleted rows (deleted = true, the app removes them). Only entries from the last 8 days are
-- scanned: older ones are outside every edit window, so they cannot change (7-day horizon + 1 day
-- of timezone slack). The cursor is (updated_at, id) of the last row the app saw; the API makes it
-- opaque. Rows carry codes and numbers only, never free text.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION app.fn_changes_since(
    p_user_id uuid, p_after_at timestamptz DEFAULT NULL, p_after_id uuid DEFAULT NULL, p_limit integer DEFAULT 500
)
RETURNS TABLE (
    kind text,
    id uuid,
    local_date date,
    version integer,
    updated_at timestamptz,
    deleted boolean,
    data jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_horizon timestamptz := now() - interval '8 days';
    v_after_at timestamptz := coalesce(p_after_at, '-infinity'::timestamptz);
    v_after_id uuid := coalesce(p_after_id, '00000000-0000-0000-0000-000000000000'::uuid);
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT c.kind, c.id, c.local_date, c.version, c.updated_at, c.deleted, c.data
    FROM (
        SELECT 'intake'::text AS kind, i.id, i.local_date, i.version, i.updated_at, i.deleted_at IS NOT NULL AS deleted,
               jsonb_build_object(
                   'logged_at', i.logged_at, 'drink_code', i.drink_code, 'custom_drink_id', i.custom_drink_id,
                   'volume_ml', i.volume_ml, 'effective_ml', i.effective_ml, 'source', i.source
               ) AS data
        FROM hydration.intake AS i
        WHERE i.user_id = p_user_id AND i.logged_at >= v_horizon
        UNION ALL
        SELECT 'meal', m.id, m.local_date, m.version, m.updated_at, m.deleted_at IS NOT NULL,
               jsonb_build_object('logged_at', m.logged_at, 'meal_type', m.meal_type, 'source', m.source)
        FROM nutrition.meal AS m
        WHERE m.user_id = p_user_id AND m.logged_at >= v_horizon
        UNION ALL
        SELECT 'workout', w.id, w.local_date, w.version, w.updated_at, w.deleted_at IS NOT NULL,
               jsonb_build_object(
                   'performed_at', w.performed_at, 'workout_type', w.workout_type,
                   'duration_min', w.duration_min, 'kcal', w.kcal
               )
        FROM activity.workout AS w
        WHERE w.user_id = p_user_id AND w.performed_at >= v_horizon
        UNION ALL
        SELECT 'sleep', s.id, s.wake_local_date, s.version, s.updated_at, s.deleted_at IS NOT NULL,
               jsonb_build_object(
                   'sleep_start', s.sleep_start, 'wake_time', s.wake_time, 'counted_min', s.counted_min
               )
        FROM sleep.entry AS s
        WHERE s.user_id = p_user_id AND s.wake_time >= v_horizon
    ) AS c
    WHERE (c.updated_at, c.id) > (v_after_at, v_after_id)
    ORDER BY c.updated_at, c.id
    LIMIT least(greatest(coalesce(p_limit, 500), 1), 501);
END
$$;
COMMENT ON FUNCTION app.fn_changes_since(uuid, timestamptz, uuid, integer) IS
'GET /sync/changes: the caller''s entries changed after (updated_at, id), incl. deletions, last 8 days';
REVOKE ALL ON FUNCTION app.fn_changes_since(uuid, timestamptz, uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION app.fn_changes_since(uuid, timestamptz, uuid, integer) TO app_rw;
