-- Targets in force on a day: the latest snapshot with effective_date <= p_on (default: the user's
-- today). Past days keep the targets that applied then (doc 06 section 1, "past days unchanged").
-- Served by uq_health_target_snapshot__user_date.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION app.fn_latest_target_snapshot(p_user_id uuid, p_on date DEFAULT NULL)
RETURNS SETOF app.health_target_snapshot
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_on date := p_on;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF v_on IS NULL THEN
        SELECT common.fn_local_date(p.timezone) INTO v_on FROM app.user_profile AS p WHERE p.user_id = p_user_id;
        v_on := coalesce(v_on, common.fn_local_date(NULL));
    END IF;
    RETURN QUERY
    SELECT s.*
    FROM app.health_target_snapshot AS s
    WHERE s.user_id = p_user_id
      AND s.effective_date <= v_on
    ORDER BY s.effective_date DESC
    LIMIT 1;
END
$$;

COMMENT ON FUNCTION app.fn_latest_target_snapshot(uuid, date) IS 'Targets in force on a day (latest snapshot on or before it)';
REVOKE ALL ON FUNCTION app.fn_latest_target_snapshot(uuid, date) FROM public;
GRANT EXECUTE ON FUNCTION app.fn_latest_target_snapshot(uuid, date) TO app_rw, app_worker, app_readonly;
