-- Help & Support (Session 14; doc 04 section 2.13, OQ-51): plain-text tickets with a reference, the
-- screenshot key must be a support/ key, 5 tickets and 5 feature requests per day, the worker hands
-- unforwarded items over once and gives up after 20 failed attempts.
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status)
VALUES ('0192f000-0000-7000-8000-000000008201', 'sp1@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at)
VALUES ('0192f000-0000-7000-8000-000000008201', 6, now());
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-000000008201', TRUE);

CREATE FUNCTION pg_temp.ticket(p_text text, p_key text DEFAULT NULL) RETURNS text LANGUAGE plpgsql AS $$
DECLARE t uuid; r text;
BEGIN
    CALL support.pr_create_ticket('0192f000-0000-7000-8000-000000008201', 'app_crash', p_text, p_key, t, r);
    RETURN r;
END
$$;
CREATE FUNCTION pg_temp.feature(p_title text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r uuid;
BEGIN
    CALL support.pr_create_feature_request('0192f000-0000-7000-8000-000000008201', p_title, 'It would help me', r);
    RETURN r;
END
$$;

SELECT matches(pg_temp.ticket('The app closes when I open reports'), '^NC-[A-Z0-9]{8}$', 'a ticket gets a short reference');
SELECT throws_ok($$SELECT pg_temp.ticket('<script>alert(1)</script>')$$, '23514', NULL, 'markup in a ticket is refused');
SELECT throws_ok($$SELECT pg_temp.ticket('crash', 'reports/x.pdf')$$, '23514', NULL, 'the screenshot key must be a support/ key');
SELECT lives_ok($$SELECT pg_temp.ticket('crash with screenshot', 'support/0192f000-0000-7000-8000-000000008299.png')$$,
    'a support screenshot key is accepted');
SELECT pg_temp.ticket('more ' || n) FROM generate_series(1, 3) AS n;
SELECT throws_like($$SELECT pg_temp.ticket('sixth today')$$, '%limit%', 'the 6th ticket in 24 hours is refused');
SELECT pg_temp.feature('Idea ' || n) FROM generate_series(1, 5) AS n;
SELECT throws_like($$SELECT pg_temp.feature('Idea six')$$, '%limit%', 'the 6th feature request in 24 hours is refused');

-- Worker hand-over.
SELECT is((SELECT count(*)::int FROM ops.fn_support_unforwarded(100)), 10, 'five tickets and five requests are waiting');
SELECT is(
    (SELECT count(*)::int FROM ops.fn_support_unforwarded(100) WHERE reply_email = 'sp1@example.test'), 10,
    'support gets the account email to reply to'
);
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM ops.fn_support_unforwarded(100) LOOP
        CALL ops.pr_mark_support_forwarded(r.kind, r.item_id, TRUE);
    END LOOP;
END $$;
SELECT is((SELECT count(*)::int FROM ops.fn_support_unforwarded(100)), 0, 'forwarded items are not sent again');

UPDATE support.ticket SET forwarded_at = NULL, forward_attempts = 19
WHERE id = (SELECT id FROM support.ticket ORDER BY created_at LIMIT 1);
DO $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM ops.fn_support_unforwarded(100) LOOP
        CALL ops.pr_mark_support_forwarded(r.kind, r.item_id, FALSE);
    END LOOP;
END $$;
SELECT is((SELECT count(*)::int FROM ops.fn_support_unforwarded(100)), 0, 'after 20 failed attempts the worker gives up');

SELECT * FROM finish();
ROLLBACK;
