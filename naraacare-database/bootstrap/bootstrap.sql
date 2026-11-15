-- One-time bootstrap of a NaraaCare database (local, staging or prod; any PostgreSQL 18 host).
-- Run with psql as the server's admin user, connected to the (already created) target database:
--   psql "host=<db host> dbname=naraacare user=<admin> sslmode=verify-full sslrootcert=<provider CA bundle>" \
--        -v mo_pw="$MIGRATION_OWNER_PASSWORD" -f bootstrap/bootstrap.sql
-- Locally, tools/local_setup.sh runs it for you. The password comes from the secret manager
-- (secret: naraacare/<env>/db/migration_owner) or, locally, from .env; never hard-code it.
-- Safe to re-run: the role is only created when missing.

\set ON_ERROR_STOP on

SELECT format(
    'CREATE ROLE migration_owner LOGIN CREATEROLE NOSUPERUSER NOBYPASSRLS PASSWORD %L', :'mo_pw'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'migration_owner') \gexec
-- Lets a non-superuser admin (as on managed PostgreSQL services) hand over ownership below.
SELECT 'GRANT migration_owner TO CURRENT_USER'
WHERE NOT pg_has_role(current_user, 'migration_owner', 'MEMBER') \gexec

SELECT format('ALTER DATABASE %I OWNER TO migration_owner', current_database()) \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database()) \gexec
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
