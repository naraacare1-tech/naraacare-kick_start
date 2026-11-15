-- Session-context helpers, text validation and updated_at triggers (Session 03).
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

-- fn_current_user_id / fn_assert_actor
SELECT throws_ok(
    'SELECT common.fn_current_user_id()', '42501', NULL, 'fn_current_user_id raises when app.user_id is unset'
);
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000000a1', TRUE);
SELECT is(
    common.fn_current_user_id(), '0192f000-0000-7000-8000-0000000000a1'::uuid,
    'fn_current_user_id returns the actor'
);
SELECT lives_ok(
    $$SELECT common.fn_assert_actor('0192f000-0000-7000-8000-0000000000a1')$$, 'fn_assert_actor accepts the actor'
);
SELECT throws_ok(
    $$SELECT common.fn_assert_actor('0192f000-0000-7000-8000-0000000000b2')$$,
    '42501', NULL, 'fn_assert_actor rejects another user (42501, API answers 404)'
);
SELECT throws_ok(
    'SELECT common.fn_assert_actor(NULL)', '42501', NULL, 'fn_assert_actor rejects NULL'
);

-- fn_validate_text: every payload rejected with 22023, valid text accepted, length enforced
SELECT is((SELECT count(*)::int FROM test_payloads), 529, 'payload fixture loaded');
DO $validate$
DECLARE
    r record;
    v_passed integer := 0;
BEGIN
    FOR r IN SELECT id, payload FROM test_payloads LOOP
        BEGIN
            PERFORM common.fn_validate_text(r.payload, 10000);
            v_passed := v_passed + 1;
        EXCEPTION WHEN invalid_parameter_value THEN
            NULL;
        END;
    END LOOP;
    CREATE TEMP TABLE validate_result AS SELECT v_passed AS passed;
END
$validate$;
SELECT is((SELECT passed FROM validate_result), 0, 'fn_validate_text rejects all 529 payloads with 22023');
SELECT is(common.fn_validate_text('Priya Sharma', 50)::text, 'Priya Sharma', 'fn_validate_text accepts plain text');
SELECT is(common.fn_validate_text(NULL, 50)::text, NULL, 'fn_validate_text passes NULL through');
SELECT throws_ok(
    $$SELECT common.fn_validate_text(repeat('a', 51), 50)$$, '22023', NULL, 'fn_validate_text enforces the maximum length'
);
SELECT throws_ok(
    $$SELECT common.fn_validate_text('<b>hi</b>', 50)$$, '22023', 'text contains markup, scripting or unsafe characters',
    'the error message never echoes the rejected value'
);

-- fn_local_date: "today" is the user's day
SELECT is(
    common.fn_local_date('Asia/Kolkata', timestamptz '2026-10-27 20:00:00+00'), date '2026-10-28',
    '20:00 UTC is already the next day in India'
);
SELECT is(
    common.fn_local_date('America/New_York', timestamptz '2026-10-27 02:00:00+00'), date '2026-10-26',
    '02:00 UTC is still the previous day in New York'
);

-- updated_at triggers cover every table that has the column
SELECT is(
    (
        SELECT array_agg(n.nspname || '.' || c.relname ORDER BY 1)
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        INNER JOIN pg_attribute AS a ON a.attrelid = c.oid AND a.attname = 'updated_at' AND NOT a.attisdropped
        WHERE n.nspname IN (
            'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND c.relkind IN ('r', 'p')
        AND NOT c.relispartition
        AND NOT EXISTS (
            SELECT 1 FROM pg_trigger AS t
            WHERE t.tgrelid = c.oid AND t.tgname = 'trg_set_updated_at' AND NOT t.tgisinternal
        )
    ),
    NULL,
    'every table with updated_at has trg_set_updated_at'
);

INSERT INTO auth.user_account (id, email, status, updated_at) VALUES
('0192f000-0000-7000-8000-0000000000a1', 'ua1@example.test', 'active', '2000-01-01');
UPDATE auth.user_account SET last_login_at = now()
WHERE id = '0192f000-0000-7000-8000-0000000000a1';
SELECT is(
    (
        SELECT updated_at FROM auth.user_account
        WHERE id = '0192f000-0000-7000-8000-0000000000a1'
    ), now(),
    'updated_at is set on UPDATE'
);
SELECT is(
    (
        SELECT updated_by FROM auth.user_account
        WHERE id = '0192f000-0000-7000-8000-0000000000a1'
    ),
    '0192f000-0000-7000-8000-0000000000a1'::uuid,
    'updated_by records the transaction actor'
);
UPDATE ref.unit SET updated_at = '2000-01-01'
WHERE code = (SELECT min(code) FROM ref.unit);
SELECT is(
    (
        SELECT u.updated_at FROM ref.unit AS u
        WHERE u.code = (SELECT min(m.code) FROM ref.unit AS m)
    ), now(),
    'tables without updated_by get updated_at too'
);

SELECT * FROM finish();
ROLLBACK;
