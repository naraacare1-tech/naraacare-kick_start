-- Security event writer (doc 07 section 4.4). Called by the API (validation rejections, authz denials,
-- rate limits, webhook rejections) and by other procedures (lockout, refresh reuse, ops alerts).
-- details must never carry user input: it is limited to a flat object whose values are numbers,
-- booleans, null or machine codes (common.code format). Anything else raises 22023, so a rejected
-- payload cannot be smuggled into the audit trail. No actor check: events are often about
-- anonymous callers or other users.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE audit.pr_log_security_event(
    p_event_type common.code,
    p_user_id uuid DEFAULT NULL,
    p_ip inet DEFAULT NULL,
    p_request_id uuid DEFAULT NULL,
    p_field_name common.code DEFAULT NULL,
    p_details jsonb DEFAULT '{}'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_details jsonb := coalesce(p_details, '{}');
    v_request text := current_setting('app.request_id', true);
BEGIN
    IF jsonb_typeof(v_details) <> 'object' THEN
        RAISE EXCEPTION 'details must be a JSON object' USING ERRCODE = '22023', DETAIL = 'INVALID_DETAILS';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM jsonb_each(v_details) AS d
        WHERE d.key !~ '^[a-z][a-z0-9_]{0,62}$'
           OR jsonb_typeof(d.value) NOT IN ('number', 'boolean', 'null', 'string')
           OR (jsonb_typeof(d.value) = 'string' AND (d.value #>> '{}') !~ '^[a-z][a-z0-9_.]{0,62}$')
    ) THEN
        RAISE EXCEPTION 'details may only contain numbers, booleans and codes'
            USING ERRCODE = '22023', DETAIL = 'INVALID_DETAILS';
    END IF;

    INSERT INTO audit.security_event (event_type, user_id, ip, request_id, field_name, details)
    VALUES (
        p_event_type, p_user_id, p_ip,
        coalesce(
            p_request_id,
            CASE WHEN v_request ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v_request::uuid END
        ),
        p_field_name, v_details
    );
END
$$;

COMMENT ON PROCEDURE audit.pr_log_security_event (common.code, uuid, inet, uuid, common.code, jsonb) IS
'Append a security event; details limited to numbers, booleans and codes (never user input)';
REVOKE ALL ON PROCEDURE audit.pr_log_security_event(common.code, uuid, inet, uuid, common.code, jsonb)
FROM public;
GRANT EXECUTE ON PROCEDURE audit.pr_log_security_event(common.code, uuid, inet, uuid, common.code, jsonb)
TO app_rw, app_worker, migration_owner;
