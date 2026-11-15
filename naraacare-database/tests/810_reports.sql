-- PDF report jobs (Session 14; doc 04 section 2.11, OQ-38): tier rules (custom range, sleep, insights
-- with AI consent), range checks, idempotency (replay returns the first job), 10 requests a day, the
-- worker lifecycle (claim -> ready + notification, retries -> failed, expiry) and ownership.
BEGIN;
SELECT no_plan();

INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-000000008101', 'rp1@example.test', 'active'),
('0192f000-0000-7000-8000-000000008102', 'rp2@example.test', 'active');
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at) VALUES
('0192f000-0000-7000-8000-000000008101', 6, now()),
('0192f000-0000-7000-8000-000000008102', 6, now());
-- 8101 STANDARD; 8102 STAR without AI consent.
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES ('0192f000-0000-7000-8000-000000008102', 'star', 'promo', now() - interval '1 day', now() + interval '30 days');

CREATE FUNCTION pg_temp.req(p_user text, p_key uuid, p_kind text, p_from date, p_to date, p_sections text[])
RETURNS text LANGUAGE plpgsql AS $$
DECLARE r uuid; s text; c boolean;
BEGIN
    PERFORM set_config('app.user_id', p_user, TRUE);
    CALL report.pr_create_report_job(p_user::uuid, p_key, p_kind, p_from, p_to, p_sections, r, s, c);
    RETURN r || '|' || s || '|' || c;
END
$$;
CREATE FUNCTION pg_temp.today() RETURNS date LANGUAGE sql AS $$ SELECT common.fn_local_date('Asia/Kolkata') $$;
CREATE FUNCTION pg_temp.s() RETURNS text LANGUAGE sql AS $$ SELECT '0192f000-0000-7000-8000-000000008101' $$;
CREATE FUNCTION pg_temp.p() RETURNS text LANGUAGE sql AS $$ SELECT '0192f000-0000-7000-8000-000000008102' $$;

-- ===== Rules =====
CREATE TEMP TABLE first AS SELECT pg_temp.req(pg_temp.s(), '0192f000-0000-7000-8000-00000000a001', 'monthly', pg_temp.today(), NULL, ARRAY['hydration']) AS r;
SELECT alike((SELECT r FROM first), '%|queued|true', 'a monthly report is open to every tier');
SELECT is(
    (SELECT period_to FROM report.report_job WHERE id = split_part((SELECT r FROM first), '|', 1)::uuid), pg_temp.today(),
    'the current month ends today'
);
SELECT is(
    pg_temp.req(pg_temp.s(), '0192f000-0000-7000-8000-00000000a001', 'monthly', pg_temp.today(), NULL, ARRAY['hydration']),
    replace((SELECT r FROM first), '|true', '|false'), 'a replay returns the first job'
);
SELECT throws_ok(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'monthly', %L, NULL, ARRAY['hydration'])$$, pg_temp.s(), pg_temp.today() + 40),
    '22023', NULL, 'a month that has not started is refused'
);
SELECT throws_like(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'custom', %L, %L, ARRAY['hydration'])$$, pg_temp.s(), pg_temp.today() - 5, pg_temp.today()),
    '%STAR%', 'custom ranges need STAR'
);
SELECT throws_like(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'monthly', %L, NULL, ARRAY['sleep'])$$, pg_temp.s(), pg_temp.today()),
    '%STAR%', 'sleep needs STAR for a month without sleep data'
);
SELECT throws_ok(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'monthly', %L, NULL, ARRAY['insights'])$$, pg_temp.s(), pg_temp.today()),
    '22023', NULL, 'insights alone is not a report'
);
SELECT alike(
    pg_temp.req(pg_temp.p(), uuidv7(), 'custom', pg_temp.today() - 5, pg_temp.today(), ARRAY['sleep', 'hydration']),
    '%|queued|true', 'STAR: custom range with sleep'
);
SELECT throws_ok(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'custom', %L, %L, ARRAY['hydration'])$$, pg_temp.p(), pg_temp.today(), pg_temp.today() - 1),
    '22023', NULL, 'from after to is refused'
);
SELECT throws_ok(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'custom', %L, %L, ARRAY['hydration'])$$, pg_temp.p(), pg_temp.today() - 400, pg_temp.today()),
    '22023', NULL, 'more than 366 days is refused'
);
SELECT throws_like(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'monthly', %L, NULL, ARRAY['hydration', 'insights'])$$, pg_temp.p(), pg_temp.today()),
    '%consent%', 'insights need the AI processing consent'
);

-- 10 a day: the STANDARD user has 1; 9 more pass, the 11th is refused.
SELECT pg_temp.req(pg_temp.s(), uuidv7(), 'monthly', pg_temp.today(), NULL, ARRAY['nutrition']) FROM generate_series(1, 9);
SELECT throws_like(
    format($$SELECT pg_temp.req(%L, uuidv7(), 'monthly', %L, NULL, ARRAY['nutrition'])$$, pg_temp.s(), pg_temp.today()),
    '%limit%', 'the 11th request in 24 hours is refused (REPORT_LIMIT_REACHED)'
);

-- ===== Ownership =====
SELECT set_config('app.user_id', pg_temp.p(), TRUE);
SELECT throws_ok(
    format($$SELECT * FROM report.fn_report_jobs(%L)$$, pg_temp.s()),
    '42501', NULL, 'nobody lists another user''s reports'
);
SELECT throws_ok(
    format($$SELECT * FROM report.fn_report_jobs(%L, %L)$$, pg_temp.p(), split_part((SELECT r FROM first), '|', 1)),
    '42501', NULL, 'another user''s report id is 404'
);

-- ===== Worker lifecycle (app_worker routines, run here as the superuser) =====
DELETE FROM report.report_job WHERE id <> split_part((SELECT r FROM first), '|', 1)::uuid;
SELECT is((SELECT count(*)::int FROM ops.fn_claim_report_jobs(5)), 1, 'the worker claims the queued job');
SELECT is((SELECT status FROM report.report_job WHERE id = split_part((SELECT r FROM first), '|', 1)::uuid), 'running', 'claimed jobs are running');
SELECT is((SELECT count(*)::int FROM ops.fn_claim_report_jobs(5)), 0, 'a running job is not claimed twice');
DO $$
DECLARE j uuid := split_part((SELECT r FROM first), '|', 1)::uuid;
BEGIN
    CALL ops.pr_finish_report_job(j, TRUE, 'reports/' || gen_random_uuid() || '.pdf', 1234, NULL);
END $$;
SELECT is((SELECT status FROM report.report_job WHERE id = split_part((SELECT r FROM first), '|', 1)::uuid), 'ready', 'a finished job is ready');
SELECT is(
    (SELECT count(*)::int FROM notify.notification WHERE user_id = pg_temp.s()::uuid AND template_code LIKE 'report%'), 1,
    'the user gets a "report ready" notification'
);
UPDATE report.report_job SET expires_at = now() - interval '1 minute' WHERE id = split_part((SELECT r FROM first), '|', 1)::uuid;
SELECT is((SELECT count(*)::int FROM ops.fn_expire_reports(10)), 1, 'expired files are handed back for deletion');

SELECT * FROM finish();
ROLLBACK;
