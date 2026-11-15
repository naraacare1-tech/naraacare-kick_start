-- Failed sign-ins for an email since its last success within a window (default 15 min, doc 07 SEC-1.6).
-- Served by ix_login_attempt__email_time.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_login_failures_recent(
    p_email common.email,
    p_window interval DEFAULT interval '15 minutes'
)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT count(*)::integer
    FROM auth.login_attempt AS la
    WHERE la.email = p_email
      AND NOT la.success
      AND la.attempted_at > now() - least(p_window, interval '1 day')
      AND la.attempted_at > coalesce((
          SELECT max(ok.attempted_at) FROM auth.login_attempt AS ok
          WHERE ok.email = p_email AND ok.success
      ), '-infinity')
$$;

COMMENT ON FUNCTION auth.fn_login_failures_recent(common.email, interval) IS
'Failed sign-ins for an email since the last success within the window (max 1 day)';
REVOKE ALL ON FUNCTION auth.fn_login_failures_recent(common.email, interval) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_login_failures_recent(common.email, interval) TO app_rw;
