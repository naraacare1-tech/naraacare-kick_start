-- Layer 3 of input validation (doc 07 section 4.5): no column may accept scripting or markup.
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

INSERT INTO auth.user_account (id, email, status)
VALUES ('0192f000-0000-7000-8000-00000000eee5', 'u44@example.test', 'active');

-- 1. Every payload is rejected by common.safe_text (the domain behind every free-text column).
SELECT
    throws_ok(
        format('SELECT %L::common.safe_text', payload),
        '23514',
        NULL,
        format('payload #%s rejected by common.safe_text', id)
    )
FROM test_payloads
ORDER BY id;

-- 2. Rejected through a real column too (domain applies on INSERT, not just casts). Only payloads
--    that fit the column's 60-character limit, so the rejection comes from the domain, not the length.
SELECT
    throws_ok(
        format(
            $$INSERT INTO nutrition.saved_meal (user_id, name) VALUES ('0192f000-0000-7000-8000-00000000eee5', %L)$$,
            payload
        ),
        '23514', NULL,
        format('payload #%s rejected by nutrition.saved_meal.name', id)
    )
FROM (
    SELECT
        id,
        payload
    FROM test_payloads
    WHERE char_length(payload) <= 60
    ORDER BY id
    LIMIT 5
) AS short_payloads;

-- 3. Legitimate text is accepted (multilingual names, apostrophes, punctuation, units).
SELECT lives_ok(format('SELECT %L::common.safe_text', v), 'accepts: ' || v)
FROM unnest(ARRAY[
    'Priya Sharma', E'O\'Brien', 'Jean-Luc', U&'\092A\094D\0930\093F\092F\093E', 'Moong Dal - 2 Katori (4 items)',
    '100% juice', 'Salt & pepper', 'Dal: 1 bowl; Roti: 2', E'Line one\nLine two', 'Is it ok? Yes!'
]) AS v;

-- 4. Catalog rule: no column uses bare text/varchar/char (or arrays of them). Every text column must use
--    a common.* domain (safe_text, code, username, ...). Generated columns are derived and exempt.
SELECT is(
    (
        SELECT array_agg(n.nspname || '.' || c.relname || '.' || a.attname ORDER BY 1)
        FROM pg_attribute AS a
        INNER JOIN pg_class AS c ON c.oid = a.attrelid
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname IN (
            'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND c.relkind IN ('r', 'p')
        AND NOT c.relispartition
        AND a.attnum > 0 AND NOT a.attisdropped
        AND a.attgenerated = ''
        AND a.atttypid IN (
            'text'::regtype, 'varchar'::regtype, 'bpchar'::regtype,
            'text[]'::regtype, 'varchar[]'::regtype
        )
    ),
    NULL,
    'no table column uses bare text/varchar: all text goes through a validating domain'
);

-- 5. Every free-text (safe_text) column has a length limit.
SELECT is(
    (
        SELECT array_agg(n.nspname || '.' || c.relname || '.' || a.attname ORDER BY 1)
        FROM pg_attribute AS a
        INNER JOIN pg_class AS c ON c.oid = a.attrelid
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE
            a.atttypid = 'common.safe_text'::regtype
            AND c.relkind IN ('r', 'p') AND NOT c.relispartition
            AND a.attnum > 0 AND NOT a.attisdropped
            AND NOT EXISTS (
                SELECT 1 FROM pg_constraint AS k
                WHERE
                    k.conrelid = c.oid AND k.contype = 'c'
                    AND (
                        pg_get_constraintdef(k.oid) LIKE '%char_length((' || a.attname || ')::text)%'
                        OR pg_get_constraintdef(k.oid) LIKE '%char_length(' || a.attname || ')%'
                    )
            )
    ),
    NULL,
    'every safe_text column has a char_length CHECK'
);

SELECT * FROM finish();
ROLLBACK;
