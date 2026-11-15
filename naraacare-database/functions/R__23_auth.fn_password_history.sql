-- Last 5 password hashes, newest first (OQ-29: a new password must differ from them). The hashes are
-- salted Argon2id, so comparison happens in the API: it verifies the candidate against each hash and
-- only then calls auth.pr_set_password. For a reset, the API sets app.user_id to the user proven by the
-- OTP (auth.pr_verify_otp) before calling this.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_password_history(p_user_id uuid)
RETURNS SETOF common.argon2_hash
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT h.password_hash
    FROM auth.password_history AS h
    WHERE h.user_id = p_user_id
    ORDER BY h.created_at DESC, h.id DESC
    LIMIT 5;
END
$$;

COMMENT ON FUNCTION auth.fn_password_history(uuid) IS 'Last 5 Argon2id hashes for the password-reuse check (API side)';
REVOKE ALL ON FUNCTION auth.fn_password_history(uuid) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_password_history(uuid) TO app_rw;
