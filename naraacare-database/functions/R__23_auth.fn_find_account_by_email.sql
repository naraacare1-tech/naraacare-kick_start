-- Account lookup for sign-in, sign-up and password reset (before any actor exists, so no actor check).
-- The email is matched in plain text (lower-cased by the API).
-- Returns the Argon2id hash because verification happens in the API (doc 07 SEC-1.1); the hash
-- never leaves the API process. Deleted accounts are not returned.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_find_account_by_email(p_email common.email)
RETURNS TABLE (
    user_id uuid,
    status common.code,
    role common.code,
    password_hash common.argon2_hash,
    email_verified_at timestamptz,
    locked_until timestamptz,
    failed_login_count smallint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT a.id, a.status, a.role, a.password_hash, a.email_verified_at, a.locked_until, a.failed_login_count
    FROM auth.user_account AS a
    WHERE a.email = p_email
      AND a.status <> 'deleted'
$$;

COMMENT ON FUNCTION auth.fn_find_account_by_email(common.email) IS
'Pre-auth account lookup by email (sign-in, sign-up, reset)';
REVOKE ALL ON FUNCTION auth.fn_find_account_by_email(common.email) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_find_account_by_email(common.email) TO app_rw;
