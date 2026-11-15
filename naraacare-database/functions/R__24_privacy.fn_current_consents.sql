-- GET /privacy/consents (doc 04 section 2.13): the latest decision per purpose (consent history is
-- append-only, so the newest row is the one in force). Purposes never answered are not listed.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION privacy.fn_current_consents(p_user_id uuid)
RETURNS TABLE (
    purpose common.code,
    granted boolean,
    policy_version common.version_label,
    recorded_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT DISTINCT ON (c.purpose) c.purpose, c.granted, c.policy_version, c.recorded_at
    FROM privacy.consent_record AS c
    WHERE c.user_id = p_user_id
    ORDER BY c.purpose, c.recorded_at DESC, c.id DESC;
END
$$;

COMMENT ON FUNCTION privacy.fn_current_consents(uuid) IS 'Latest consent decision per purpose for the actor';
REVOKE ALL ON FUNCTION privacy.fn_current_consents(uuid) FROM public;
GRANT EXECUTE ON FUNCTION privacy.fn_current_consents(uuid) TO app_rw, app_readonly;
