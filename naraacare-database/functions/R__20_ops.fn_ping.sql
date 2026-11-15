-- Readiness probe for the API and worker (GET /health/ready). Proves that the login role can reach
-- the database and execute functions, without touching any table. Not SECURITY DEFINER: it reads
-- nothing, so it runs with the caller's own (minimal) rights.
CREATE OR REPLACE FUNCTION ops.fn_ping()
RETURNS integer
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$ SELECT 1 $$;

COMMENT ON FUNCTION ops.fn_ping() IS 'Readiness probe: returns 1 (no table access)';
REVOKE ALL ON FUNCTION ops.fn_ping() FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_ping() TO app_rw, app_worker, app_readonly;
