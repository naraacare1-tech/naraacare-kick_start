-- Session 16: layer 3 of input validation over the WHOLE catalog (doc 07 section 4.5). Test 060 checks
-- the safe_text domain in depth; this one is driven by pg_catalog, so a table, schema or column added
-- later is covered without editing the test:
--   1. no table column in any application schema is bare text/varchar/char (generated columns exempt);
--   2. every payload is rejected by every text domain any table column uses;
--   3. every safe_text column, in every schema, has a length CHECK;
--   4. every jsonb column has a CHECK (shape and size), so no unbounded free-form text hides in JSON.
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

CREATE TEMP VIEW app_columns AS
SELECT
    n.nspname,
    c.relname,
    c.oid AS relid,
    a.attname,
    a.atttypid,
    a.attgenerated
FROM pg_attribute AS a
INNER JOIN pg_class AS c ON c.oid = a.attrelid
INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE
    c.relkind IN ('r', 'p')
    AND NOT c.relispartition
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND n.nspname !~ '^pg_'
    AND n.nspname NOT IN ('information_schema', 'public');

-- The application schemas are found, not listed (a forgotten new schema was the gap this closes).
SELECT cmp_ok(
    (SELECT count(DISTINCT nspname)::integer FROM app_columns), '>=', 16,
    'all application schemas are scanned'
);

-- 1. No bare text anywhere.
SELECT is(
    (
        SELECT array_agg(nspname || '.' || relname || '.' || attname ORDER BY 1)
        FROM app_columns
        WHERE
            attgenerated = ''
            AND atttypid IN (
                'text'::regtype, 'varchar'::regtype, 'bpchar'::regtype,
                'text[]'::regtype, 'varchar[]'::regtype
            )
    ),
    NULL,
    'no table column in any schema uses bare text/varchar'
);

-- 2. Every payload against every text domain in use.
CREATE FUNCTION pg_temp.accepts(p_value text, p_domain regtype) RETURNS boolean
LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE format('SELECT %L::%s', p_value, p_domain);
    RETURN true;
EXCEPTION WHEN check_violation OR invalid_text_representation OR string_data_right_truncation THEN
    RETURN false;
END
$$;

CREATE TEMP TABLE text_domains AS
SELECT DISTINCT ac.atttypid::regtype AS domain_type
FROM app_columns AS ac
INNER JOIN pg_type AS t ON t.oid = ac.atttypid
WHERE t.typtype = 'd' AND t.typbasetype IN ('text'::regtype, 'varchar'::regtype)
  AND t.typnamespace = 'common'::regnamespace;

SELECT cmp_ok((SELECT count(*)::integer FROM text_domains), '>=', 15, 'text domains found');

SELECT is(
    (
        SELECT array_agg(DISTINCT d.domain_type::text ORDER BY d.domain_type::text)
        FROM text_domains AS d
        CROSS JOIN test_payloads AS p
        WHERE pg_temp.accepts(p.payload, d.domain_type)
    ),
    NULL,
    format('no text domain accepts any of the %s payloads', (SELECT count(*) FROM test_payloads))
);

-- Sanity: the probe itself works (a valid value is accepted by its domain).
SELECT ok(pg_temp.accepts('priya@example.com', 'common.email'), 'probe accepts a valid email');
SELECT ok(pg_temp.accepts(E'O\'Brien''s dal', 'common.safe_text'), 'probe accepts plain text');

-- 3. Length limits on every free-text column.
SELECT is(
    (
        SELECT array_agg(ac.nspname || '.' || ac.relname || '.' || ac.attname ORDER BY 1)
        FROM app_columns AS ac
        WHERE
            ac.atttypid = 'common.safe_text'::regtype
            AND NOT EXISTS (
                SELECT 1 FROM pg_constraint AS k
                WHERE
                    k.conrelid = ac.relid AND k.contype = 'c'
                    AND (
                        pg_get_constraintdef(k.oid) LIKE '%char_length((' || ac.attname || ')::text)%'
                        OR pg_get_constraintdef(k.oid) LIKE '%char_length(' || ac.attname || ')%'
                    )
            )
    ),
    NULL,
    'every safe_text column in every schema has a char_length CHECK'
);

-- 4. Every jsonb column is constrained. Exempt: the audit trail's row images, written only by the
--    audit trigger from rows that already passed their own constraints (no client writes them).
SELECT is(
    (
        SELECT array_agg(ac.nspname || '.' || ac.relname || '.' || ac.attname ORDER BY 1)
        FROM app_columns AS ac
        WHERE
            ac.atttypid = 'jsonb'::regtype
            AND (ac.nspname, ac.relname) <> ('audit', 'change_log')
            AND NOT EXISTS (
                SELECT 1 FROM pg_constraint AS k
                WHERE
                    k.conrelid = ac.relid AND k.contype = 'c'
                    AND pg_get_constraintdef(k.oid) LIKE '%' || ac.attname || '%'
            )
    ),
    NULL,
    'every jsonb column has a CHECK constraint'
);

SELECT * FROM finish();
ROLLBACK;
