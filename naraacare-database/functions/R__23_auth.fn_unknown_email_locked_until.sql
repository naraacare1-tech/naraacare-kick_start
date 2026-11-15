-- Lockout for an email with NO account (doc 07 T26): without it, five wrong passwords would lock a
-- real account but never an unknown email, which tells an attacker which emails are registered.
-- Derived from auth.login_attempt (no extra state): while 5+ failures fall within 15 minutes, the
-- email is "locked" from its last failure for the same backoff as a real account
-- (5-9 failures in a day -> 1 min, 10-14 -> 5 min, 15-19 -> 15 min, 20+ -> 60 min). Attempts made
-- while locked are not recorded (the API answers 423 first), exactly as for a real account.
-- Returns NULL when an account exists (its own locked_until applies) or when not locked.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_unknown_email_locked_until(p_email common.email)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT CASE WHEN locked_until > now() THEN locked_until END
    FROM (
        SELECT max(la.attempted_at) + CASE
            WHEN count(*) >= 20 THEN interval '60 minutes'
            WHEN count(*) >= 15 THEN interval '15 minutes'
            WHEN count(*) >= 10 THEN interval '5 minutes'
            ELSE interval '1 minute'
        END AS locked_until
        FROM auth.login_attempt AS la
        WHERE la.email = p_email
          AND NOT la.success
          AND la.attempted_at > now() - interval '1 day'
        HAVING auth.fn_login_failures_recent(p_email, interval '15 minutes') >= 5
    ) AS lock
    WHERE NOT EXISTS (
        SELECT 1 FROM auth.user_account AS a WHERE a.email = p_email AND a.status <> 'deleted'
    )
$$;

COMMENT ON FUNCTION auth.fn_unknown_email_locked_until(common.email) IS
'Lockout for an email with no account, derived from login attempts (no enumeration via lockout)';
REVOKE ALL ON FUNCTION auth.fn_unknown_email_locked_until(common.email) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_unknown_email_locked_until(common.email) TO app_rw;
