-- Smoke test: required extensions exist and pgTAP itself is not part of the schema migrations.
BEGIN;
SELECT plan(7);

SELECT has_extension('pgcrypto', 'pgcrypto is installed');
SELECT has_extension('pg_trgm', 'pg_trgm is installed');
SELECT has_extension('btree_gist', 'btree_gist is installed');
SELECT has_extension('unaccent', 'unaccent is installed');
SELECT has_extension('citext', 'citext is installed');

SELECT is(
    current_setting('server_version_num')::int / 10000,
    18,
    'running on PostgreSQL 18'
);

SELECT ok(
    EXISTS (
        SELECT 1 FROM public.flyway_schema_history
        WHERE version = '001' AND success
    ),
    'V001 recorded as successful in flyway_schema_history'
);

SELECT * FROM finish();
ROLLBACK;
