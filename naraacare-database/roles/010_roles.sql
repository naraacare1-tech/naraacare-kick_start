-- Roles and grants (doc 05 §7). Roles are cluster-wide, so creation is idempotent.
-- Passwords come from Flyway placeholders (env FLYWAY_PLACEHOLDERS_*); prod rotates them via the secret manager afterwards.
--
--   migration_owner  owns schemas/tables, runs Flyway (created by bootstrap)
--   api_definer      NOLOGIN; owns API functions/procedures; DML on tables; subject to RLS
--   app_rw           API login; EXECUTE on API functions only (granted per function from Session 03)
--   app_worker       worker login; app_rw rights + maintenance functions (Session 03)
--   app_readonly     read-replica login; EXECUTE on read-only functions only
--   reporting        BI login; SELECT on aggregated report.v_* views only (Session 14)

DO $roles$
DECLARE
    r record;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'api_definer') THEN
        CREATE ROLE api_definer NOLOGIN NOINHERIT NOBYPASSRLS;
    END IF;

    FOR r IN
        SELECT * FROM (VALUES
            ('app_rw',       '${app_rw_password}',       200),
            ('app_worker',   '${app_worker_password}',    50),
            ('app_readonly', '${app_readonly_password}', 100),
            ('reporting',    '${reporting_password}',     10)
        ) AS t (role_name, pw, conn_limit)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r.role_name) THEN
            IF r.pw = '' OR r.pw LIKE '$%{%' THEN
                RAISE EXCEPTION 'Missing Flyway placeholder password for role %', r.role_name;
            END IF;
            EXECUTE format(
                'CREATE ROLE %I LOGIN NOINHERIT NOBYPASSRLS NOCREATEDB NOCREATEROLE CONNECTION LIMIT %s PASSWORD %L',
                r.role_name, r.conn_limit, r.pw
            );
        END IF;
    END LOOP;
END
$roles$;

-- migration_owner may act as api_definer (needed to hand function ownership to it), without inheriting rights.
-- (Inheriting api_definer's DML adds nothing: migration_owner already owns every table.)
GRANT api_definer TO migration_owner;

-- Database access and per-database session limits.
DO $db$
BEGIN
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO app_rw, app_worker, app_readonly, reporting', current_database());
    EXECUTE format('ALTER ROLE app_rw IN DATABASE %I SET statement_timeout = %L', current_database(), '5s');
    EXECUTE format('ALTER ROLE app_rw IN DATABASE %I SET idle_in_transaction_session_timeout = %L', current_database(), '10s');
    EXECUTE format('ALTER ROLE app_worker IN DATABASE %I SET statement_timeout = %L', current_database(), '120s');
    EXECUTE format('ALTER ROLE app_readonly IN DATABASE %I SET statement_timeout = %L', current_database(), '10s');
    EXECUTE format('ALTER ROLE app_readonly IN DATABASE %I SET default_transaction_read_only = %L', current_database(), 'on');
END
$db$;

-- Schema usage: app roles may resolve names but get no table privileges (functions only).
GRANT USAGE ON SCHEMA common, auth, app, ref, activity, nutrition, hydration, sleep, billing, notify, privacy, audit, ops
TO api_definer, app_rw, app_worker, app_readonly;

-- api_definer gets DML on every table migration_owner creates from now on.
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner
IN SCHEMA auth, app, ref, activity, nutrition, hydration, sleep, billing, notify, privacy, audit, ops
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner
IN SCHEMA auth, app, ref, activity, nutrition, hydration, sleep, billing, notify, privacy, audit, ops
GRANT USAGE, SELECT ON SEQUENCES TO api_definer;

-- No function is executable by PUBLIC unless explicitly granted. Functions are always created by
-- migration_owner (then handed to api_definer with ALTER ... OWNER TO, which keeps this ACL), so the
-- default privilege of migration_owner covers them; tests/010 verifies no function is PUBLIC-executable.
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner REVOKE EXECUTE ON FUNCTIONS FROM public;

REVOKE EXECUTE ON FUNCTION common.current_user_id() FROM public;
GRANT EXECUTE ON FUNCTION common.current_user_id() TO api_definer;
