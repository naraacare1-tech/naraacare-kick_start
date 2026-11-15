-- POST /auth/otp/resend (doc 04 section 2.1): a new code for an existing challenge. Same rate rules as
-- auth.pr_create_otp_challenge (30 s cooldown, 5 sends per email per hour; send_count <= 5 per
-- challenge). The new code restarts the 5-minute window and the 3 attempts; old guesses are void
-- because the old code is gone.
-- o_status: ok | rate_limited (o_retry_after_s) | not_found | consumed
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_resend_otp(
    p_challenge_id uuid,
    p_code common.otp_code,
    INOUT o_status text DEFAULT NULL,
    INOUT o_retry_after_s integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_challenge auth.otp_challenge%ROWTYPE;
    v_sent_last_hour integer;
    v_oldest_in_hour timestamptz;
BEGIN
    o_retry_after_s := NULL;
    SELECT * INTO v_challenge FROM auth.otp_challenge WHERE id = p_challenge_id FOR UPDATE;
    IF NOT FOUND THEN
        o_status := 'not_found';
        RETURN;
    END IF;
    IF v_challenge.consumed_at IS NOT NULL THEN
        o_status := 'consumed';
        RETURN;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('auth.otp:' || v_challenge.email, 0));

    IF v_challenge.last_sent_at > now() - interval '30 seconds' THEN
        o_status := 'rate_limited';
        o_retry_after_s := ceil(extract(EPOCH FROM v_challenge.last_sent_at + interval '30 seconds' - now()))::integer;
        RETURN;
    END IF;

    SELECT coalesce(sum(c.send_count), 0), min(c.last_sent_at) INTO v_sent_last_hour, v_oldest_in_hour
    FROM auth.otp_challenge AS c
    WHERE c.email = v_challenge.email AND c.last_sent_at > now() - interval '1 hour';
    IF v_sent_last_hour >= 5 OR v_challenge.send_count >= 5 THEN
        o_status := 'rate_limited';
        o_retry_after_s := greatest(
            1, ceil(extract(EPOCH FROM coalesce(v_oldest_in_hour, now()) + interval '1 hour' - now()))::integer
        );
        RETURN;
    END IF;

    UPDATE auth.otp_challenge
    SET code = p_code,
        expires_at = now() + interval '5 minutes',
        attempts = 0,
        send_count = send_count + 1,
        last_sent_at = now()
    WHERE id = p_challenge_id;
    o_status := 'ok';
END
$$;

COMMENT ON PROCEDURE auth.pr_resend_otp (uuid, common.otp_code, text, integer) IS
'Resend an OTP (new code, new 5-minute window) within the cooldown and hourly limits';
REVOKE ALL ON PROCEDURE auth.pr_resend_otp(uuid, common.otp_code, text, integer) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_resend_otp(uuid, common.otp_code, text, integer) TO app_rw;
