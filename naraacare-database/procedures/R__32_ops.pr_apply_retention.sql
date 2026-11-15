-- Time-based retention for partitioned tables (doc 05 sections 9 and 11): for each ops.partition_config
-- row with retention_months, monthly partitions that END on or before
-- (first day of p_as_of's month - retention_months) are detached and dropped. Dropping a partition is
-- O(1) and leaves no dead rows, unlike DELETE. Tables with retention_months NULL (health logs) are
-- never touched. DEFAULT partitions are never dropped.
-- The worker job runs this only after confirming the latest database backup succeeded (doc 11).
-- Owned by migration_owner (DDL); names come from the catalog and are quoted with %I (SEC-4.1).
CREATE OR REPLACE PROCEDURE ops.pr_apply_retention(
    p_as_of date DEFAULT NULL,
    INOUT o_dropped integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    cfg record;
    part record;
    v_as_of date := coalesce(p_as_of, (now() AT TIME ZONE 'UTC')::date);
    v_cutoff date;
    v_month date;
BEGIN
    o_dropped := 0;
    PERFORM set_config('lock_timeout', '5s', true);

    FOR cfg IN
        SELECT * FROM ops.partition_config WHERE retention_months IS NOT NULL ORDER BY parent_table
    LOOP
        v_cutoff := (date_trunc('month', v_as_of) - make_interval(months => cfg.retention_months))::date;
        FOR part IN
            SELECT n.nspname AS schema_name, c.relname AS table_name
            FROM pg_catalog.pg_inherits AS i
            INNER JOIN pg_catalog.pg_class AS c ON c.oid = i.inhrelid
            INNER JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE i.inhparent = cfg.parent_table::regclass
              AND c.relname ~ '_p[0-9]{4}_[0-9]{2}$'
            ORDER BY c.relname
        LOOP
            v_month := to_date(right(part.table_name, 7), 'YYYY_MM');
            CONTINUE WHEN (v_month + interval '1 month')::date > v_cutoff;
            EXECUTE format('ALTER TABLE %s DETACH PARTITION %I.%I', cfg.parent_table::regclass, part.schema_name, part.table_name);
            EXECUTE format('DROP TABLE %I.%I', part.schema_name, part.table_name);
            o_dropped := o_dropped + 1;
        END LOOP;
    END LOOP;
END
$$;

COMMENT ON PROCEDURE ops.pr_apply_retention (date, integer) IS
'Detach and drop monthly partitions older than partition_config.retention_months';
REVOKE ALL ON PROCEDURE ops.pr_apply_retention(date, integer) FROM public;
GRANT EXECUTE ON PROCEDURE ops.pr_apply_retention(date, integer) TO app_worker;
