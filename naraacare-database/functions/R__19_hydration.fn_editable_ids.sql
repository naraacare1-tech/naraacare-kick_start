-- Internal: the edit rule for the hydration avatar (doc 06 section 1, OQ-53). Only the user's last 2
-- non-deleted drinks (by logged_at) and last 2 workouts (by performed_at) may change, and only while
-- they are less than 7 days old. Not granted to any login role; called from the definer
-- functions/procedures, which run as api_definer under RLS (own rows only).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION hydration.fn_editable_intake_ids(p_user_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT i.id
    FROM (
        SELECT i.id, i.logged_at
        FROM hydration.intake AS i
        WHERE i.user_id = p_user_id AND i.deleted_at IS NULL
        ORDER BY i.logged_at DESC, i.id DESC
        LIMIT 2
    ) AS i
    WHERE i.logged_at > now() - interval '7 days';
$$;

COMMENT ON FUNCTION hydration.fn_editable_intake_ids(uuid) IS
'Internal: ids of the drinks still editable (last 2 by logged_at, within 7 days)';
REVOKE ALL ON FUNCTION hydration.fn_editable_intake_ids(uuid) FROM public;

CREATE OR REPLACE FUNCTION activity.fn_editable_workout_ids(p_user_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT w.id
    FROM (
        SELECT w.id, w.performed_at
        FROM activity.workout AS w
        WHERE w.user_id = p_user_id AND w.deleted_at IS NULL
        ORDER BY w.performed_at DESC, w.id DESC
        LIMIT 2
    ) AS w
    WHERE w.performed_at > now() - interval '7 days';
$$;

COMMENT ON FUNCTION activity.fn_editable_workout_ids(uuid) IS
'Internal: ids of the workouts still deletable (last 2 by performed_at, within 7 days)';
REVOKE ALL ON FUNCTION activity.fn_editable_workout_ids(uuid) FROM public;
