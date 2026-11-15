-- Row-Level Security (doc 05 section 7, doc 07 SEC-4.4).
BEGIN;
SELECT no_plan();

-- Every user-owned table has RLS enabled (not forced: the owner runs cross-user maintenance).
SELECT is(
    (
        SELECT array_agg(n.nspname || '.' || c.relname ORDER BY 1)
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        INNER JOIN pg_attribute AS a ON a.attrelid = c.oid AND a.attname = 'user_id' AND NOT a.attisdropped
        WHERE
            n.nspname IN ('app', 'activity', 'nutrition', 'hydration', 'sleep', 'notify', 'privacy')
            AND c.relkind IN ('r', 'p')
            AND NOT c.relispartition
            AND n.nspname || '.' || c.relname <> 'privacy.consent_record'
            AND NOT c.relrowsecurity
    ),
    NULL,
    'RLS enabled on every user-owned table'
);
SELECT is(
    (
        SELECT count(*)::int FROM pg_class
        WHERE relforcerowsecurity
    ),
    0,
    'RLS is not forced (owner-run maintenance keeps working)'
);
SELECT policies_are('hydration', 'intake', ARRAY['own_rows'], 'hydration.intake has the own_rows policy');

-- Fixture: two users with a profile and an intake each (inserted as superuser).
INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-00000000aaa1', 'u11@example.test', 'active'),
('0192f000-0000-7000-8000-00000000bbb2', 'u22@example.test', 'active');
INSERT INTO app.user_profile (user_id) VALUES
('0192f000-0000-7000-8000-00000000aaa1'),
('0192f000-0000-7000-8000-00000000bbb2');
INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source) VALUES
(uuidv7(), now(), '0192f000-0000-7000-8000-00000000aaa1', current_date, 'water', 250, 1, 250, 'manual'),
(uuidv7(), now(), '0192f000-0000-7000-8000-00000000bbb2', current_date, 'water', 500, 1, 500, 'manual');

-- Act as api_definer (the owner of every API function) for user A. pgTAP lives in schema public,
-- which is locked down in production; let api_definer call it for this rolled-back test only.
GRANT USAGE ON SCHEMA public TO api_definer;
SET LOCAL ROLE api_definer;
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-00000000aaa1', TRUE);

SELECT is((SELECT count(*)::int FROM app.user_profile), 1, 'user A sees only their own profile');
SELECT is((SELECT sum(volume_ml)::int FROM hydration.intake), 250, 'user A sees only their own intakes');
SELECT throws_ok(
    $$INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source)
      VALUES (uuidv7(), now(), '0192f000-0000-7000-8000-00000000bbb2', current_date, 'water', 100, 1, 100, 'manual')$$,
    '42501', NULL, 'user A cannot insert rows for user B'
);
SELECT is_empty(
    $$UPDATE hydration.intake SET version = version + 1
      WHERE user_id = '0192f000-0000-7000-8000-00000000bbb2' RETURNING id$$,
    'user A cannot update user B rows (0 rows affected)'
);

SELECT set_config('app.user_id', '', TRUE);
SELECT is((SELECT count(*)::int FROM hydration.intake), 0, 'no rows visible when app.user_id is not set');

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
