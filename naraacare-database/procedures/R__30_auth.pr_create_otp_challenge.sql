-- New email OTP challenge (doc 07 SEC-1.3): 5-minute expiry, 3 attempts, single use.
-- The API generates the 6-digit code; it is stored in plain text and compared by the API.
-- Rate rules, enforced here so every caller obeys them:
--   * 30 s cooldown since the last send for the same email and purpose
--   * at most 5 sends per email per rolling hour (sum of send_count of challenges sent in the last hour;
--     this slightly over-counts, which errs on the safe side)
-- A new challenge kills older open ones for the same email and purpose (only the newest code works).
-- Outcomes are returned in o_status, never raised, so the caller decides the HTTP answer:
--   ok | rate_limited (o_retry_after_s set) | no_account (password_reset/reauth for an unknown email:
--   the API still answers generically, OQ-26) | already_verified (email_verification, active account)
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_create_otp_challenge(
    p_email common.email,
    p_purpose common.code,
    p_code common.otp_code,
    INOUT o_challenge_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL,
    INOUT o_retry_after_s integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_user_id uuid;
    v_status common.code;
    v_last_sent timestamptz;
    v_sent_last_hour integer;
    v_oldest_in_hour timestamptz;
BEGIN
    o_challenge_id := NULL;
    o_retry_after_s := NULL;
    IF p_purpose NOT IN ('email_verification', 'password_reset', 'reauth') THEN
        RAISE EXCEPTION 'unknown OTP purpose' USING ERRCODE = '22023', DETAIL = 'INVALID_PURPOSE';
    END IF;

    SELECT a.id, a.status INTO v_user_id, v_status
    FROM auth.user_account AS a
    WHERE a.email = p_email AND a.status <> 'deleted';

    IF v_user_id IS NULL THEN
        o_status := 'no_account';
        RETURN;
    END IF;
    IF p_purpose = 'email_verification' AND v_status <> 'pending_verification' THEN
        o_status := 'already_verified';
        RETURN;
    END IF;

    -- Serialise concurrent requests for the same email so the counters below cannot be raced.
    PERFORM pg_advisory_xact_lock(hashtextextended('auth.otp:' || p_email, 0));

    SELECT max(c.last_sent_at) INTO v_last_sent
    FROM auth.otp_challenge AS c
    WHERE c.email = p_email AND c.purpose = p_purpose;
    IF v_last_sent > now() - interval '30 seconds' THEN
        o_status := 'rate_limited';
        o_retry_after_s := ceil(extract(EPOCH FROM v_last_sent + interval '30 seconds' - now()))::integer;
        RETURN;
    END IF;

    SELECT coalesce(sum(c.send_count), 0), min(c.last_sent_at) INTO v_sent_last_hour, v_oldest_in_hour
    FROM auth.otp_challenge AS c
    WHERE c.email = p_email AND c.last_sent_at > now() - interval '1 hour';
    IF v_sent_last_hour >= 5 THEN
        o_status := 'rate_limited';
        o_retry_after_s := greatest(1, ceil(extract(EPOCH FROM v_oldest_in_hour + interval '1 hour' - now()))::integer);
        RETURN;
    END IF;

    UPDATE auth.otp_challenge AS c
    SET attempts = 3
    WHERE c.email = p_email AND c.purpose = p_purpose AND c.consumed_at IS NULL AND c.attempts < 3;

    INSERT INTO auth.otp_challenge (user_id, email, purpose, code, expires_at)
    VALUES (v_user_id, p_email, p_purpose, p_code, now() + interval '5 minutes')
    RETURNING id INTO o_challenge_id;
    o_status := 'ok';
END
$$;

COMMENT ON PROCEDURE auth.pr_create_otp_challenge (common.email, common.code, common.otp_code, uuid, text, integer)
IS 'New OTP challenge with 30 s cooldown and 5/h/email limit; returns ok | rate_limited | no_account | already_verified';
REVOKE ALL ON PROCEDURE auth.pr_create_otp_challenge(common.email, common.code, common.otp_code, uuid, text, integer)
FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_create_otp_challenge(common.email, common.code, common.otp_code, uuid, text, integer)
TO app_rw;
