-- Records the outcome of an OTP check (doc 07 SEC-1.3). The API compares the code with the Argon2id
-- hash (auth.fn_get_otp_challenge) and passes p_code_ok; this procedure enforces expiry, the 3-attempt
-- limit and single use atomically under a row lock. A wrong code must be COUNTED, so failures are
-- returned in o_status instead of raised (raising would roll the counter back).
-- A correct email_verification code activates the account.
-- o_status: ok | invalid (o_attempts_left > 0) | dead (no attempts left) | expired | consumed | not_found
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_verify_otp(
    p_challenge_id uuid,
    p_code_ok boolean,
    INOUT o_user_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL,
    INOUT o_attempts_left integer DEFAULT NULL,
    INOUT o_purpose text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_challenge auth.otp_challenge%ROWTYPE;
BEGIN
    o_user_id := NULL;
    o_attempts_left := NULL;
    o_purpose := NULL;
    SELECT * INTO v_challenge FROM auth.otp_challenge WHERE id = p_challenge_id FOR UPDATE;
    IF NOT FOUND THEN
        o_status := 'not_found';
        RETURN;
    END IF;
    o_purpose := v_challenge.purpose;

    IF v_challenge.consumed_at IS NOT NULL THEN
        o_status := 'consumed';
    ELSIF v_challenge.attempts >= 3 THEN
        o_status := 'dead';
        o_attempts_left := 0;
    ELSIF v_challenge.expires_at <= now() THEN
        o_status := 'expired';
    ELSIF NOT coalesce(p_code_ok, FALSE) THEN
        UPDATE auth.otp_challenge SET attempts = attempts + 1 WHERE id = p_challenge_id;
        o_attempts_left := 3 - (v_challenge.attempts + 1);
        o_status := CASE WHEN o_attempts_left = 0 THEN 'dead' ELSE 'invalid' END;
    ELSE
        UPDATE auth.otp_challenge SET consumed_at = now() WHERE id = p_challenge_id;
        o_user_id := v_challenge.user_id;
        o_status := 'ok';
        IF v_challenge.purpose = 'email_verification' THEN
            UPDATE auth.user_account
            SET status = 'active', email_verified_at = now()
            WHERE id = v_challenge.user_id AND status = 'pending_verification';
        END IF;
    END IF;
END
$$;

COMMENT ON PROCEDURE auth.pr_verify_otp (uuid, boolean, uuid, text, integer, text) IS
'Apply an OTP check: attempts, expiry, single use; activates the account on email verification';
REVOKE ALL ON PROCEDURE auth.pr_verify_otp(uuid, boolean, uuid, text, integer, text) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_verify_otp(uuid, boolean, uuid, text, integer, text) TO app_rw;
