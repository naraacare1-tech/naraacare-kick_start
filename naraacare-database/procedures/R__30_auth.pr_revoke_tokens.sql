-- Logout (doc 07 SEC-1.6): p_scope 'family' revokes one device session (p_family_id), 'all' every
-- session of the user, optionally keeping p_keep_family_id (password change keeps the current device).
-- Push-device registrations are left alone (doc 04: logout-all keeps devices' push tokens).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_revoke_tokens(
    p_user_id uuid,
    p_scope common.code,
    p_reason common.code,
    p_family_id uuid DEFAULT NULL,
    p_keep_family_id uuid DEFAULT NULL,
    INOUT o_revoked integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_scope NOT IN ('family', 'all') OR (p_scope = 'family' AND p_family_id IS NULL) THEN
        RAISE EXCEPTION 'invalid revocation scope' USING ERRCODE = '22023', DETAIL = 'INVALID_SCOPE';
    END IF;
    IF p_reason NOT IN ('logout', 'logout_all', 'password_change', 'deletion', 'admin') THEN
        RAISE EXCEPTION 'invalid revocation reason' USING ERRCODE = '22023', DETAIL = 'INVALID_REASON';
    END IF;

    UPDATE auth.refresh_token
    SET revoked_at = now(), revoked_reason = p_reason
    WHERE user_id = p_user_id
      AND revoked_at IS NULL
      AND (p_scope = 'all' OR family_id = p_family_id)
      AND family_id IS DISTINCT FROM p_keep_family_id;
    GET DIAGNOSTICS o_revoked = ROW_COUNT;
END
$$;

COMMENT ON PROCEDURE auth.pr_revoke_tokens (uuid, common.code, common.code, uuid, uuid, integer) IS
'Revoke one refresh-token family or all of a user''s families (optionally keeping one)';
REVOKE ALL ON PROCEDURE auth.pr_revoke_tokens(uuid, common.code, common.code, uuid, uuid, integer) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_revoke_tokens(uuid, common.code, common.code, uuid, uuid, integer) TO app_rw, app_worker;
