-- Daily partition maintenance (doc 05 section 11), run by the worker as app_worker.
-- For every ops.partition_config row: makes sure the DEFAULT partition exists and creates monthly
-- partitions <table>_pYYYY_MM for the month of p_as_of through +premake_months (explicit UTC bounds,
-- same naming as V012). Idempotent: existing partitions are skipped.
-- A DEFAULT partition must stay empty (rows there mean a month was missing when they arrived). If one
-- has rows: RAISE WARNING + an 'ops_alert' security event, and creating an overlapping month is skipped
-- for that table instead of failing the whole run.
-- Owned by migration_owner (the table owner): DDL needs ownership, and RLS must not hide rows from the
-- DEFAULT check. Dynamic SQL only via format('%I'/'%L') on names from ops.partition_config (SEC-4.1).
-- lock_timeout 5 s: never queue behind long transactions on a hot table; the next daily run retries.
CREATE OR REPLACE PROCEDURE ops.pr_ensure_partitions(
    p_as_of date DEFAULT NULL,
    INOUT o_created integer DEFAULT NULL,
    INOUT o_alerts integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    cfg record;
    m integer;
    v_as_of date := coalesce(p_as_of, (now() AT TIME ZONE 'UTC')::date);
    v_month date;
    v_schema text;
    v_table text;
    v_name text;
    v_lo text;
    v_hi text;
    v_default_has_rows boolean;
BEGIN
    o_created := 0;
    o_alerts := 0;
    PERFORM set_config('lock_timeout', '5s', true);

    FOR cfg IN SELECT * FROM ops.partition_config ORDER BY parent_table LOOP
        v_schema := split_part(cfg.parent_table, '.', 1);
        v_table := split_part(cfg.parent_table, '.', 2);

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I DEFAULT',
            v_schema, v_table || '_default', v_schema, v_table
        );
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM %I.%I)', v_schema, v_table || '_default')
        INTO v_default_has_rows;
        IF v_default_has_rows THEN
            o_alerts := o_alerts + 1;
            RAISE WARNING 'DEFAULT partition of % contains rows', cfg.parent_table;
            CALL audit.pr_log_security_event(
                'ops_alert', NULL, NULL, NULL, NULL,
                jsonb_build_object('check', 'default_partition_not_empty', 'table', cfg.parent_table)
            );
        END IF;

        FOR m IN 0 .. cfg.premake_months LOOP
            v_month := (date_trunc('month', v_as_of) + make_interval(months => m))::date;
            v_name := v_table || '_p' || to_char(v_month, 'YYYY_MM');
            CONTINUE WHEN to_regclass(format('%I.%I', v_schema, v_name)) IS NOT NULL;

            v_lo := to_char(v_month, 'YYYY-MM-DD');
            v_hi := to_char((v_month + interval '1 month')::date, 'YYYY-MM-DD');
            IF cfg.bound_type = 'timestamptz' THEN
                v_lo := v_lo || ' 00:00:00+00';
                v_hi := v_hi || ' 00:00:00+00';
            END IF;
            BEGIN
                EXECUTE format(
                    'CREATE TABLE %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                    v_schema, v_name, v_schema, v_table, v_lo, v_hi
                );
                o_created := o_created + 1;
            EXCEPTION WHEN check_violation THEN
                -- Rows for this month already sit in DEFAULT: needs a manual move (runbook, doc 11).
                o_alerts := o_alerts + 1;
                RAISE WARNING 'cannot create %.%: DEFAULT partition holds rows for that month', v_schema, v_name;
            END;
        END LOOP;
    END LOOP;
END
$$;

COMMENT ON PROCEDURE ops.pr_ensure_partitions (date, integer, integer) IS
'Create DEFAULT + current..+premake monthly partitions; alert when a DEFAULT partition has rows';
REVOKE ALL ON PROCEDURE ops.pr_ensure_partitions(date, integer, integer) FROM public;
GRANT EXECUTE ON PROCEDURE ops.pr_ensure_partitions(date, integer, integer) TO app_worker;
