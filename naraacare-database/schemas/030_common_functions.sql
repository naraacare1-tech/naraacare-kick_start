-- Current application user for RLS policies. NULL when not set (or reset to '' after a
-- transaction-local set_config), so policies match no rows instead of erroring.
CREATE OR REPLACE FUNCTION common.current_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$ SELECT nullif(current_setting('app.user_id', true), '')::uuid $$;

COMMENT ON FUNCTION common.current_user_id() IS
'app.user_id set per transaction by the API via set_config(..., true); used by RLS policies';
