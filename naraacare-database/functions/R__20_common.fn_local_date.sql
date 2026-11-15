-- The user's calendar day for a timestamp. "Today" for targets, summaries and streaks is always
-- the day in the user's own timezone (app.user_profile.timezone), never the server's.
CREATE OR REPLACE FUNCTION common.fn_local_date(p_timezone common.iana_timezone, p_at timestamptz DEFAULT now())
RETURNS date
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$ SELECT (p_at AT TIME ZONE coalesce(p_timezone, 'Asia/Kolkata'))::date $$;

COMMENT ON FUNCTION common.fn_local_date(common.iana_timezone, timestamptz) IS
'Calendar date of p_at in the given IANA timezone';
REVOKE ALL ON FUNCTION common.fn_local_date(common.iana_timezone, timestamptz) FROM public;
GRANT EXECUTE ON FUNCTION common.fn_local_date(common.iana_timezone, timestamptz) TO api_definer;
