-- Monthly RANGE partitions for the social tables (Session 12), same scheme as
-- tables/_initial_partitions.sql: a DEFAULT partition plus the current UTC month through
-- +premake_months; ops.pr_ensure_partitions keeps creating future months. Chat lives as long as its
-- circle (doc 05 section 9, OQ-48); feed events are kept 13 months (the feed shows recent days).

INSERT INTO ops.partition_config (parent_table, bound_type, premake_months, retention_months) VALUES
('social.activity_event', 'timestamptz', 3, 13),
('social.chat_message', 'timestamptz', 3, NULL)
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
    FOR cfg IN SELECT * FROM ops.partition_config WHERE parent_table LIKE 'social.%' ORDER BY parent_table LOOP
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
