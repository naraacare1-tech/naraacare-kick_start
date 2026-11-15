-- Records a sign-in attempt and applies lockout (doc 07 SEC-1.6). Call it after the API has checked
-- the password (or found no account; the attempt is still recorded so unknown emails look identical:
-- they answer 'locked' after the same failures, see auth.fn_unknown_email_locked_until).
--   * success: counters reset, last_login_at set
--   * failure: failed_login_count + 1; when 5 or more failures fall within 15 minutes (since the last
--     success) the account is locked. Backoff grows with consecutive failures:
--     5-9 -> 1 min, 10-14 -> 5 min, 15-19 -> 15 min, 20+ -> 60 min; a 'lockout' security event is logged
--     and the API emails a notice.
-- Per-IP limits live in the API (in memory), independent of this, so attackers cannot lock out users at
-- scale without hitting IP limits. Returned, not raised, so the counters persist.
-- o_status: ok | failed | locked (o_locked_until)
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_record_login_attempt(
    p_email common.email,
    p_ip inet,
    p_success boolean,
    INOUT o_status text DEFAULT NULL,
    INOUT o_locked_until timestamptz DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_user_id uuid;
    v_failed integer;
    v_recent integer;
    v_lock interval;
BEGIN
    o_locked_until := NULL;
    INSERT INTO auth.login_attempt (email, ip, success) VALUES (p_email, p_ip, p_success);

    SELECT a.id INTO v_user_id
    FROM auth.user_account AS a
    WHERE a.email = p_email AND a.status <> 'deleted'
    FOR UPDATE;

    IF p_success THEN
        IF v_user_id IS NOT NULL THEN
            UPDATE auth.user_account
            SET failed_login_count = 0, locked_until = NULL, last_login_at = now()
            WHERE id = v_user_id;
        END IF;
        o_status := 'ok';
        RETURN;
    END IF;

    o_status := 'failed';
    IF v_user_id IS NULL THEN
        -- No account: same answer as a real one (doc 07 T26), no counters or security event.
        o_locked_until := auth.fn_unknown_email_locked_until(p_email);
        IF o_locked_until IS NOT NULL THEN
            o_status := 'locked';
        END IF;
        RETURN;
    END IF;

    UPDATE auth.user_account
    SET failed_login_count = least(failed_login_count + 1, 10000)
    WHERE id = v_user_id
    RETURNING failed_login_count INTO v_failed;

    v_recent := auth.fn_login_failures_recent(p_email, interval '15 minutes');
    IF v_recent >= 5 THEN
        v_lock := CASE
            WHEN v_failed >= 20 THEN interval '60 minutes'
            WHEN v_failed >= 15 THEN interval '15 minutes'
            WHEN v_failed >= 10 THEN interval '5 minutes'
            ELSE interval '1 minute'
        END;
        UPDATE auth.user_account SET locked_until = now() + v_lock WHERE id = v_user_id
        RETURNING locked_until INTO o_locked_until;
        o_status := 'locked';
        CALL audit.pr_log_security_event(
            'lockout', v_user_id, p_ip, NULL, NULL,
            jsonb_build_object('failed_count', v_failed, 'lock_minutes', extract(EPOCH FROM v_lock)::integer / 60)
        );
    END IF;
END
$$;

COMMENT ON PROCEDURE auth.pr_record_login_attempt (common.email, inet, boolean, text, timestamptz) IS
'Record a sign-in attempt; lockout after 5 failures in 15 min with 1/5/15/60 min backoff';
REVOKE ALL ON PROCEDURE auth.pr_record_login_attempt(common.email, inet, boolean, text, timestamptz)
FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_record_login_attempt(common.email, inet, boolean, text, timestamptz)
TO app_rw;
