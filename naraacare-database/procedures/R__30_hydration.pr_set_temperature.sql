-- PUT /hydration/temperature (doc 04 section 2.5, doc 06 section 3.5, OQ-04). STAR only: STANDARD is
-- always computed at 25 C, so a STANDARD request is refused (UPGRADE_REQUIRED) and nothing changes
-- (doc 06 section 3.11). The new temperature applies from now on; hours already passed keep the old
-- drain rate (piecewise integration in the status engine). Stored in C, 15.0..40.0 (1 decimal).
-- Errors: 42501 not the actor, P0001 UPGRADE_REQUIRED / ONBOARDING_INCOMPLETE, 22023 out of range.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE hydration.pr_set_temperature(
    p_user_id uuid,
    p_temperature_c numeric,
    INOUT o_local_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_features jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_temperature_c IS NULL OR p_temperature_c NOT BETWEEN 15 AND 40 OR p_temperature_c <> round(p_temperature_c, 1) THEN
        RAISE EXCEPTION 'temperature must be 15.0..40.0 C' USING ERRCODE = '22023', DETAIL = 'TEMPERATURE_INVALID';
    END IF;
    SELECT p.timezone INTO v_timezone
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF NOT coalesce((v_features ->> 'advanced_hydration')::boolean, FALSE) THEN
        RAISE EXCEPTION 'temperature needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;

    o_local_date := common.fn_local_date(v_timezone);
    INSERT INTO hydration.temperature_log (user_id, temperature_c, effective_from, local_date)
    VALUES (p_user_id, p_temperature_c, now(), o_local_date);
END
$$;

COMMENT ON PROCEDURE hydration.pr_set_temperature (uuid, numeric, date) IS
'STAR: set the temperature from now on (15-40 C); STANDARD -> UPGRADE_REQUIRED';
REVOKE ALL ON PROCEDURE hydration.pr_set_temperature(uuid, numeric, date) FROM public;
GRANT EXECUTE ON PROCEDURE hydration.pr_set_temperature(uuid, numeric, date) TO app_rw;
