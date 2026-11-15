-- OTP challenge state for verification. The API compares the code (constant time) and then calls auth.pr_verify_otp, which re-checks expiry/attempts/single use under a
-- row lock, so a race between two verifications cannot get extra attempts.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_get_otp_challenge(p_challenge_id uuid)
RETURNS TABLE (
    challenge_id uuid,
    user_id uuid,
    purpose common.code,
    code common.otp_code,
    expires_at timestamptz,
    attempts_left integer,
    is_usable boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        c.id, c.user_id, c.purpose, c.code, c.expires_at, 3 - c.attempts,
        (c.consumed_at IS NULL AND c.attempts < 3 AND c.expires_at > now())
    FROM auth.otp_challenge AS c
    WHERE c.id = p_challenge_id
$$;

COMMENT ON FUNCTION auth.fn_get_otp_challenge(uuid) IS 'OTP challenge state and code for API-side verification';
REVOKE ALL ON FUNCTION auth.fn_get_otp_challenge(uuid) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_get_otp_challenge(uuid) TO app_rw;
