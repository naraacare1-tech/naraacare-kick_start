-- POST /auth/signup (doc 04 section 2.1): account in pending_verification + email OTP challenge.
-- Email and OTP code arrive in plain text (email lower-cased by the API); the password as an Argon2id hash.
--   * active/locked/pending_deletion account with this email -> o_status email_registered (OQ-26)
--   * pending_verification account -> sign-up is repeated: the password hash is replaced and a new
--     challenge issued. Only the device holding the new challenge_id can finish, so an attacker who
--     signs up with someone else's email gains nothing without the code from that inbox.
-- The first password also goes into auth.password_history (reuse check, OQ-29).
-- Consents (terms/privacy) are recorded by the API in the same transaction with
-- privacy.pr_record_consent after it sets app.user_id to o_user_id.
-- o_status: ok | email_registered | rate_limited (o_retry_after_s)
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_create_account(
    p_email common.email,
    p_password_hash common.argon2_hash,
    p_installation_id uuid,
    p_code common.otp_code,
    INOUT o_user_id uuid DEFAULT NULL,
    INOUT o_challenge_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL,
    INOUT o_retry_after_s integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_status common.code;
BEGIN
    o_challenge_id := NULL;
    o_retry_after_s := NULL;
    PERFORM pg_advisory_xact_lock(hashtextextended('auth.signup:' || p_email, 0));

    SELECT a.id, a.status INTO o_user_id, v_status
    FROM auth.user_account AS a
    WHERE a.email = p_email;

    IF o_user_id IS NOT NULL AND v_status <> 'pending_verification' THEN
        o_user_id := NULL;
        o_status := 'email_registered';
        RETURN;
    END IF;

    IF o_user_id IS NULL THEN
        INSERT INTO auth.user_account (email, password_hash, installation_id)
        VALUES (p_email, p_password_hash, p_installation_id)
        RETURNING id INTO o_user_id;
    END IF;

    -- Challenge first: when it is rate limited nothing else may change (the repeated sign-up is refused).
    CALL auth.pr_create_otp_challenge(
        p_email, 'email_verification', p_code, o_challenge_id, o_status, o_retry_after_s
    );
    IF o_status <> 'ok' THEN
        o_user_id := NULL;
        RETURN;
    END IF;

    IF v_status = 'pending_verification' THEN
        UPDATE auth.user_account
        SET password_hash = p_password_hash, installation_id = p_installation_id
        WHERE id = o_user_id;
        DELETE FROM auth.password_history WHERE user_id = o_user_id;
    END IF;
    INSERT INTO auth.password_history (user_id, password_hash) VALUES (o_user_id, p_password_hash);
END
$$;

COMMENT ON PROCEDURE auth.pr_create_account (
    common.email, common.argon2_hash, uuid, common.otp_code,
    uuid, uuid, text, integer
) IS 'Sign-up: pending account + verification OTP; ok | email_registered | rate_limited';
REVOKE ALL ON PROCEDURE auth.pr_create_account(
    common.email, common.argon2_hash, uuid, common.otp_code,
    uuid, uuid, text, integer
) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_create_account(
    common.email, common.argon2_hash, uuid, common.otp_code,
    uuid, uuid, text, integer
) TO app_rw;
