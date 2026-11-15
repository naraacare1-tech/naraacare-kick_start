-- Offline sync feed (Session 14; doc 04 section 2.14): the caller's changes after a cursor, oldest
-- first, including deletions, keyset-paged without duplicates or gaps, only the last 8 days, never
-- another user's rows, codes and numbers only (no free text).
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-000000008301', 'sy1@example.test', 'active'),
('0192f000-0000-7000-8000-000000008302', 'sy2@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at) VALUES
('0192f000-0000-7000-8000-000000008301', 6, now()),
('0192f000-0000-7000-8000-000000008302', 6, now());

-- Five intakes for user 1 changed one second apart, one of them deleted, one 10 days old; one for user 2.
INSERT INTO hydration.intake (
    id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source, updated_at, deleted_at
)
SELECT
    ('0192f000-0000-7000-8000-0000000083a' || n)::uuid,
    now() - (10 - n) * interval '1 minute',
    '0192f000-0000-7000-8000-000000008301',
    current_date,
    'water', 100 * n, 1, 100 * n, 'manual',
    now() - (10 - n) * interval '1 second',
    CASE WHEN n = 3 THEN now() - (10 - n) * interval '1 second' END
FROM generate_series(1, 5) AS n;
INSERT INTO hydration.intake (id, logged_at, user_id, local_date, drink_code, volume_ml, hydration_factor, effective_ml, source, updated_at)
VALUES
('0192f000-0000-7000-8000-0000000083b1', now() - interval '10 days', '0192f000-0000-7000-8000-000000008301',
 current_date - 10, 'water', 250, 1, 250, 'manual', now()),
('0192f000-0000-7000-8000-0000000083c1', now(), '0192f000-0000-7000-8000-000000008302',
 current_date, 'water', 250, 1, 250, 'manual', now());

SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000008301', TRUE);
CREATE TEMP TABLE all_rows AS SELECT * FROM app.fn_changes_since('0192f000-0000-7000-8000-000000008301', NULL, NULL, 500);

SELECT is((SELECT count(*)::int FROM all_rows), 5, 'all five recent changes, nothing older than 8 days');
SELECT is(
    (SELECT array_agg(id ORDER BY updated_at, id) FROM all_rows),
    ARRAY(SELECT ('0192f000-0000-7000-8000-0000000083a' || n)::uuid FROM generate_series(1, 5) AS n),
    'oldest change first'
);
SELECT is((SELECT deleted FROM all_rows WHERE id = '0192f000-0000-7000-8000-0000000083a3'), TRUE, 'deletions are included (tombstones)');
SELECT is((SELECT count(*)::int FROM all_rows WHERE id = '0192f000-0000-7000-8000-0000000083c1'), 0, 'another user''s rows never appear');
SELECT is(
    (SELECT count(*)::int FROM all_rows AS r, jsonb_each(r.data) AS e
     WHERE jsonb_typeof(e.value) = 'string' AND e.value #>> '{}' !~ '^[a-z0-9_:+.T -]*$'),
    0, 'payloads carry codes, numbers and timestamps only'
);

-- Paging with the cursor of the last row seen: 2 + 2 + 1, no duplicates, no gaps.
CREATE TEMP TABLE pages (n integer, id uuid, updated_at timestamptz);
DO $$
DECLARE c_at timestamptz; c_id uuid; r record; page integer := 0; got integer;
BEGIN
    LOOP
        page := page + 1;
        got := 0;
        FOR r IN SELECT * FROM app.fn_changes_since('0192f000-0000-7000-8000-000000008301', c_at, c_id, 2) LOOP
            INSERT INTO pages VALUES (page, r.id, r.updated_at);
            c_at := r.updated_at;
            c_id := r.id;
            got := got + 1;
        END LOOP;
        EXIT WHEN got = 0 OR page > 10;
    END LOOP;
END $$;
SELECT is((SELECT count(DISTINCT id)::int FROM pages), 5, 'paging returns every row');
SELECT is((SELECT count(*)::int FROM pages), 5, 'and none twice');
SELECT is((SELECT max(n) FROM pages), 3, 'pages of 2 + 2 + 1 (the next page is empty)');

-- An edit after the cursor shows up again.
UPDATE hydration.intake SET volume_ml = 999, effective_ml = 999, updated_at = now() + interval '1 second', version = version + 1
WHERE id = '0192f000-0000-7000-8000-0000000083a1';
SELECT is(
    (SELECT array_agg(id) FROM app.fn_changes_since(
        '0192f000-0000-7000-8000-000000008301', (SELECT max(updated_at) FROM all_rows),
        (SELECT id FROM all_rows ORDER BY updated_at DESC, id DESC LIMIT 1), 500)),
    ARRAY['0192f000-0000-7000-8000-0000000083a1'::uuid], 'an entry edited after the cursor comes back'
);

SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000008302', TRUE);
SELECT throws_ok(
    $$SELECT * FROM app.fn_changes_since('0192f000-0000-7000-8000-000000008301')$$,
    '42501', NULL, 'nobody reads another user''s change feed'
);

SELECT * FROM finish();
ROLLBACK;
