-- Monthly partitions exist and rows route correctly (doc 05 section 11).
BEGIN;
SELECT no_plan();

SELECT is(
    (
        SELECT array_agg(cfg.parent_table ORDER BY 1)
        FROM ops.partition_config AS cfg
        WHERE NOT EXISTS (
            SELECT 1 FROM pg_inherits AS i INNER JOIN pg_class AS p ON p.oid = i.inhrelid
            WHERE i.inhparent = cfg.parent_table::regclass AND pg_get_expr(p.relpartbound, p.oid) = 'DEFAULT'
        )
    ),
    NULL,
    'every partitioned table has a DEFAULT partition'
);

SELECT is(
    (
        SELECT array_agg(cfg.parent_table || ' +' || m ORDER BY 1)
        FROM ops.partition_config AS cfg
        CROSS JOIN generate_series(0, 3) AS m
        WHERE to_regclass(
            cfg.parent_table || '_p'
            || to_char(date_trunc('month', now() AT TIME ZONE 'UTC') + make_interval(months => m), 'YYYY_MM')
        ) IS NULL
    ),
    NULL,
    'partitions exist for the current month and the next 3 months'
);

SELECT ok(
    (
        SELECT relkind = 'p' FROM pg_class
        WHERE oid = 'nutrition.meal'::regclass
    ),
    'nutrition.meal is a partitioned table'
);

-- Routing: a row logged now lands in this month's partition, never in DEFAULT.
INSERT INTO auth.user_account (id, email, status)
VALUES ('0192f000-0000-7000-8000-00000000ccc3', 'u33@example.test', 'active');
INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
VALUES ('0192f000-0000-7000-8000-00000000ddd4', now(), '0192f000-0000-7000-8000-00000000ccc3', current_date, 'water', 250, 1, 250, 'manual');

SELECT is(
    (
        SELECT tableoid::regclass::text FROM hydration.intake
        WHERE id = '0192f000-0000-7000-8000-00000000ddd4'
    ),
    'hydration.intake_p' || to_char(now() AT TIME ZONE 'UTC', 'YYYY_MM'),
    'an intake logged now is stored in the current month partition'
);

SELECT * FROM finish();
ROLLBACK;
