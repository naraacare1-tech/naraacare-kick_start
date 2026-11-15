-- Index rules (doc 05 section 6).
BEGIN;
SELECT no_plan();

-- Every explicitly created index (not backing a PK/UNIQUE/EXCLUDE constraint, not on a partition)
-- documents the query it serves.
SELECT is(
    (
        SELECT array_agg(n.nspname || '.' || ic.relname ORDER BY 1)
        FROM pg_index AS i
        INNER JOIN pg_class AS ic ON ic.oid = i.indexrelid
        INNER JOIN pg_class AS tc ON tc.oid = i.indrelid
        INNER JOIN pg_namespace AS n ON n.oid = ic.relnamespace
        WHERE n.nspname IN (
            'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND NOT tc.relispartition
        AND NOT EXISTS (
            SELECT 1 FROM pg_constraint AS c
            WHERE c.conindid = i.indexrelid
        )
        AND coalesce(obj_description(ic.oid, 'pg_class'), '') NOT LIKE 'serves: %'
    ),
    NULL,
    'every index has a "serves: ..." comment'
);

-- Every foreign key has an index whose leading columns are the FK columns, except FKs into
-- reference tables (ref.*, billing.store_product), whose rows are never deleted or re-keyed.
SELECT is(
    (
        SELECT array_agg(c.conrelid::regclass || ' -> ' || c.confrelid::regclass ORDER BY 1)
        FROM pg_constraint AS c
        INNER JOIN pg_class AS tc ON tc.oid = c.conrelid
        INNER JOIN pg_namespace AS n ON n.oid = tc.relnamespace
        INNER JOIN pg_class AS rc ON rc.oid = c.confrelid
        INNER JOIN pg_namespace AS rn ON rn.oid = rc.relnamespace
        WHERE
            c.contype = 'f'
            AND n.nspname IN (
                'auth', 'app', 'activity', 'nutrition', 'hydration', 'sleep',
                'billing', 'notify', 'privacy', 'audit', 'ops'
            )
            AND NOT tc.relispartition
            AND c.conparentid = 0
            AND rn.nspname <> 'ref'
            AND (rn.nspname, rc.relname) <> ('billing', 'store_product')
            AND NOT EXISTS (
                SELECT 1 FROM pg_index AS i
                WHERE
                    i.indrelid = c.conrelid
                    AND (i.indkey::int2[])[0:cardinality(c.conkey) - 1] = c.conkey
            )
    ),
    NULL,
    'every foreign key (outside ref lookups) has a supporting index'
);

-- Spot checks of the most important access paths
SELECT has_index('nutrition', 'food_item', 'ix_food_item__name_trgm', 'trigram food search index');
SELECT has_index('hydration', 'intake', 'ix_intake__user_day', 'hydration day-scan covering index');
SELECT has_index('nutrition', 'meal', 'ix_meal__user_day', 'meal day-list covering index');
SELECT has_index('app', 'user_profile', 'uq_user_profile__username', 'unique username index');
SELECT has_index('audit', 'change_log', 'brin_change_log__occurred_at', 'BRIN on audit time');

SELECT is(
    (
        SELECT am.amname FROM pg_class AS c INNER JOIN pg_am AS am ON am.oid = c.relam
        WHERE c.oid = 'nutrition.ix_food_item__name_trgm'::regclass
    ),
    'gin', 'food name search uses GIN'
);
SELECT is(
    (
        SELECT am.amname FROM pg_class AS c INNER JOIN pg_am AS am ON am.oid = c.relam
        WHERE c.oid = 'audit.brin_change_log__occurred_at'::regclass
    ),
    'brin', 'audit time index is BRIN'
);

SELECT * FROM finish();
ROLLBACK;
