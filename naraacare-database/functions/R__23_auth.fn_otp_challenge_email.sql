-- Email of an OTP challenge's account, so POST /auth/otp/resend can send the new code
-- (doc 04 section 2.1). The challenge id is a random UUID the device received from sign-up or
-- forgot-password.
-- Pre-auth (no actor yet), like auth.fn_get_otp_challenge. Consumed challenges return no row.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_otp_challenge_email(p_challenge_id uuid)
RETURNS TABLE (
    user_id uuid,
    purpose common.code,
    email common.email
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT c.user_id, c.purpose, a.email
    FROM auth.otp_challenge AS c
    INNER JOIN auth.user_account AS a ON a.id = c.user_id
    WHERE c.id = p_challenge_id
      AND c.consumed_at IS NULL
      AND a.status <> 'deleted'
$$;

COMMENT ON FUNCTION auth.fn_otp_challenge_email(uuid) IS
'Email for an open OTP challenge (resend); pre-auth';
REVOKE ALL ON FUNCTION auth.fn_otp_challenge_email(uuid) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_otp_challenge_email(uuid) TO app_rw;
