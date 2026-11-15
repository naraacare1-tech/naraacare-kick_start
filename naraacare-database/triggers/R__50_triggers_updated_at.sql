-- updated_at (and updated_by) maintenance on every table that has the column (doc 05 section 1).
-- Discovered from the catalog so new tables are covered when this script is re-applied; tests/110 fails
-- if a table with updated_at lacks the trigger (e.g. a later migration added one without changing
-- this file: bump the version line below to make Flyway re-run it).
-- Version: 2026.10.27-1
-- Triggers on a partitioned parent are cloned to every partition automatically.
DO $triggers$
DECLARE
    t record;
BEGIN
    FOR t IN
        SELECT
            n.nspname AS schema_name,
            c.relname AS table_name,
            EXISTS (
                SELECT 1 FROM pg_attribute AS b
                WHERE b.attrelid = c.oid AND b.attname = 'updated_by' AND NOT b.attisdropped
            ) AS has_updated_by
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        INNER JOIN pg_attribute AS a ON a.attrelid = c.oid AND a.attname = 'updated_at' AND NOT a.attisdropped
        WHERE n.nspname IN (
            'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND c.relkind IN ('r', 'p')
        AND NOT c.relispartition
        ORDER BY 1, 2
    LOOP
        EXECUTE format(
            'CREATE OR REPLACE TRIGGER trg_set_updated_at BEFORE UPDATE ON %I.%I FOR EACH ROW EXECUTE FUNCTION %s()',
            t.schema_name, t.table_name,
            CASE WHEN t.has_updated_by THEN 'common.trg_fn_set_updated_at_by' ELSE 'common.trg_fn_set_updated_at' END
        );
    END LOOP;
END
$triggers$;
