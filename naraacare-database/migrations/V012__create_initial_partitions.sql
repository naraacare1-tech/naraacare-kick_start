-- V012__create_initial_partitions: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/_initial_partitions.sql
-- Monthly RANGE partitions (doc 05 sections 1 and 11).
-- Creates a DEFAULT partition (must stay empty; alerts in Session 03) and partitions for the current
-- UTC month through +premake_months. Bounds are explicit UTC so results never depend on session TimeZone.
-- From Session 03, ops.pr_ensure_partitions (daily job) keeps creating future months.

INSERT INTO ops.partition_config (parent_table, bound_type, premake_months, retention_months) VALUES
('activity.workout', 'timestamptz', 3, NULL),
('audit.change_log', 'timestamptz', 3, 36),
('audit.security_event', 'timestamptz', 3, 12),
('hydration.daily_summary', 'date', 3, NULL),
('hydration.intake', 'timestamptz', 3, NULL),
('notify.notification', 'timestamptz', 3, 3),
('nutrition.daily_summary', 'date', 3, NULL),
('nutrition.meal', 'timestamptz', 3, NULL),
('nutrition.meal_item', 'timestamptz', 3, NULL)
ON CONFLICT (parent_table) DO NOTHING;

DO $partitions$
DECLARE
    cfg record;
    m integer;
    month_start date;
    parent_schema text;
    parent_name text;
    lo text;
    hi text;
BEGIN
    FOR cfg IN SELECT * FROM ops.partition_config ORDER BY parent_table LOOP
        parent_schema := split_part(cfg.parent_table, '.', 1);
        parent_name := split_part(cfg.parent_table, '.', 2);

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I DEFAULT',
            parent_schema, parent_name || '_default', parent_schema, parent_name
        );

        FOR m IN 0..cfg.premake_months LOOP
            month_start := (date_trunc('month', now() AT TIME ZONE 'UTC') + make_interval(months => m))::date;
            lo := to_char(month_start, 'YYYY-MM-DD');
            hi := to_char((month_start + interval '1 month')::date, 'YYYY-MM-DD');
            IF cfg.bound_type = 'timestamptz' THEN
                lo := lo || ' 00:00:00+00';
                hi := hi || ' 00:00:00+00';
            END IF;
            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                parent_schema, parent_name || '_p' || to_char(month_start, 'YYYY_MM'),
                parent_schema, parent_name, lo, hi
            );
        END LOOP;
    END LOOP;
END
$partitions$;
