-- Privacy (Session 15; doc 05 section 9, doc 07 SEC-7, OQ-47, OQ-48): consent records are append-only
-- and required consents cannot be withdrawn; re-consent only for a newer published major version;
-- one export a day (idempotent); deletion is scheduled 30 days out and can be cancelled; erasure
-- removes every trace of the user id (catalog scan), keeps hashed consent/payment proof, hands
-- circles on, and leaves a hashed deletion log.
BEGIN;
SELECT no_plan();

CREATE FUNCTION pg_temp.u(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(36864 + n), 12, '0'))::uuid
$$;
INSERT INTO auth.user_account (id, email, status, email_verified_at)
SELECT pg_temp.u(n), 'pv' || n || '@example.test', 'active', now() FROM generate_series(1, 3) AS n;
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at, username, full_name)
SELECT pg_temp.u(n), 6, now(), 'privacy.user' || n, 'Privacy Person' || n FROM generate_series(1, 3) AS n;

CREATE FUNCTION pg_temp.act(p_user uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.user_id', p_user::text, TRUE) $$;
CREATE FUNCTION pg_temp.consent(p_user uuid, p_purpose text, p_version text, p_granted boolean) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE i bigint;
BEGIN PERFORM pg_temp.act(p_user); CALL privacy.pr_record_consent(p_user, p_purpose, p_version, p_granted, NULL, NULL, i); END $$;

-- ===== Consents =====
INSERT INTO ref.policy_document (doc_type, version, url, published_at) VALUES
('terms', '1.0', 'https://naraacare.app/terms/1.0', now() - interval '2 days'),
('privacy', '1.0', 'https://naraacare.app/privacy/1.0', now() - interval '2 days');
SELECT pg_temp.consent(pg_temp.u(1), 'terms', '1.0', TRUE);
SELECT pg_temp.consent(pg_temp.u(1), 'privacy', '1.0', TRUE);
SELECT pg_temp.consent(pg_temp.u(1), 'ai_processing', '1.0', TRUE);
SELECT throws_ok($$UPDATE privacy.consent_record SET granted = FALSE$$, NULL, NULL, 'consent records cannot be changed');
SELECT throws_ok($$DELETE FROM privacy.consent_record$$, NULL, NULL, 'nor deleted');
SELECT throws_ok($$SELECT pg_temp.consent(pg_temp.u(1), 'terms', '1.0', FALSE)$$, '22023', NULL,
    'terms cannot be withdrawn (that is account deletion)');
SELECT throws_ok($$SELECT pg_temp.consent(pg_temp.u(1), 'health_data', '1.0', FALSE)$$, '22023', NULL,
    'nor health data');
SELECT lives_ok($$SELECT pg_temp.consent(pg_temp.u(1), 'ai_processing', '1.0', FALSE)$$, 'optional consents can be withdrawn');
SELECT is((SELECT count(*)::int FROM privacy.consent_record WHERE user_id = pg_temp.u(1) AND purpose = 'ai_processing'), 2,
    'a withdrawal is a new record, the history stays');

-- ===== Re-consent gate =====
INSERT INTO ref.policy_document (doc_type, version, url, published_at) VALUES
('terms', '1.4', 'https://naraacare.app/terms/1.4', now() - interval '1 day'),
('privacy', '2.0', 'https://naraacare.app/privacy/2.0', NULL);
SELECT pg_temp.act(pg_temp.u(1));
SELECT is(jsonb_array_length(privacy.fn_privacy_status(pg_temp.u(1)) -> 'reconsent'), 0,
    'a minor version and an unpublished draft ask for nothing');
UPDATE ref.policy_document SET published_at = now() - interval '1 hour' WHERE doc_type = 'privacy' AND version = '2.0';
SELECT is(privacy.fn_privacy_status(pg_temp.u(1)) -> 'reconsent' -> 0 ->> 'current_version', '2.0',
    'a published new major version asks for re-consent');
SELECT pg_temp.consent(pg_temp.u(1), 'privacy', '2.0', TRUE);
SELECT pg_temp.act(pg_temp.u(1));
SELECT is(jsonb_array_length(privacy.fn_privacy_status(pg_temp.u(1)) -> 'reconsent'), 0, 'accepting it clears the gate');

-- ===== Export =====
CREATE FUNCTION pg_temp.export(p_user uuid, p_key uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE e uuid; s text; c boolean;
BEGIN PERFORM pg_temp.act(p_user); CALL privacy.pr_request_export(p_user, p_key, e, s, c); RETURN e || '|' || c; END $$;
CREATE TEMP TABLE ex AS SELECT pg_temp.export(pg_temp.u(1), '0192f000-0000-7000-8000-00000000e001') AS r;
SELECT is(pg_temp.export(pg_temp.u(1), '0192f000-0000-7000-8000-00000000e001'), replace((SELECT r FROM ex), '|true', '|false'),
    'the same Idempotency-Key returns the same export');
SELECT throws_like($$SELECT pg_temp.export(pg_temp.u(1), uuidv7())$$, '%', 'a second export within 24 hours is refused');
CREATE TEMP TABLE dump AS SELECT ops.fn_export_user(pg_temp.u(1))::text AS t;
SELECT matches((SELECT t FROM dump), 'Privacy Person1', 'the export contains the user''s own data');
SELECT doesnt_match((SELECT t FROM dump), 'argon2|password_hash|token_hash', 'and no secrets');
SELECT doesnt_match((SELECT t FROM dump), 'Privacy Person2', 'and nothing of anyone else');

-- ===== Deletion: schedule, cancel, erase =====
CREATE FUNCTION pg_temp.request_deletion(p_user uuid) RETURNS timestamptz LANGUAGE plpgsql AS $$
DECLARE t timestamptz; c boolean;
BEGIN PERFORM pg_temp.act(p_user); CALL privacy.pr_request_deletion(p_user, t, c); RETURN t; END $$;
SELECT ok(pg_temp.request_deletion(pg_temp.u(2)) BETWEEN now() + interval '29 days 23 hours' AND now() + interval '30 days 1 hour',
    'deletion is scheduled 30 days out');
SELECT is((SELECT count(*)::int FROM ops.fn_due_deletions(10) WHERE user_id = pg_temp.u(2)), 0, 'not due during the grace period');
DO $$ DECLARE c boolean; BEGIN PERFORM pg_temp.act(pg_temp.u(2)); CALL privacy.pr_cancel_deletion(pg_temp.u(2), c); END $$;
SELECT is(privacy.fn_privacy_status(pg_temp.u(2)) -> 'deletion', 'null'::jsonb, 'a cancelled deletion is gone');

-- User 3 shares a circle with user 2 (user 3 is admin) and has a consent and a payment to archive.
DO $$
DECLARE c uuid; n integer; s text;
BEGIN
    PERFORM pg_temp.act(pg_temp.u(3));
    CALL social.pr_create_circle(pg_temp.u(3), 'Erasure test', ARRAY[pg_temp.u(2)], ARRAY['hydration'], c, n);
    PERFORM pg_temp.act(pg_temp.u(2));
    CALL social.pr_respond_invite(pg_temp.u(2), c, 'accept', ARRAY['hydration'], s);
    CREATE TEMP TABLE circ AS SELECT c AS id;
END $$;
SELECT pg_temp.consent(pg_temp.u(3), 'terms', '1.0', TRUE);
INSERT INTO billing.subscription (
    id, user_id, platform, product_id, purchase_token, status, auto_renew, current_period_start,
    current_period_end, environment, last_verified_at
) VALUES (
    '0192f000-0000-7000-8000-00000000e9a1', pg_temp.u(3), 'google_play', 'star_monthly', 'tok-900', 'active', TRUE,
    now() - interval '1 day', now() + interval '29 days', 'sandbox', now()
);
INSERT INTO billing.store_transaction (subscription_id, store_transaction_id, type, amount_micros, currency, occurred_at)
VALUES ('0192f000-0000-7000-8000-00000000e9a1', 'GPA.900-1', 'purchase', 199000000, 'INR', now());

SELECT pg_temp.request_deletion(pg_temp.u(3));
UPDATE privacy.deletion_request SET requested_at = now() - interval '31 days', scheduled_for = now() - interval '1 minute' WHERE user_id = pg_temp.u(3);
SELECT is((SELECT count(*)::int FROM ops.fn_due_deletions(10) WHERE user_id = pg_temp.u(3)), 1, 'due once the date has passed');
SELECT set_config('app.user_id', '', TRUE);
DO $$ DECLARE a integer; BEGIN CALL ops.pr_delete_user(pg_temp.u(3), a); END $$;

SELECT is((SELECT count(*)::int FROM auth.user_account WHERE id = pg_temp.u(3)), 0, 'the account is gone');
SELECT is(pg_temp.member_role, 'admin', 'the remaining member becomes admin')
FROM (SELECT role AS member_role FROM social.circle_member WHERE circle_id = (SELECT id FROM circ) AND user_id = pg_temp.u(2)) AS pg_temp;
SELECT is(
    (SELECT count(*)::int FROM privacy.consent_archive WHERE user_hash = encode(sha256(convert_to(pg_temp.u(3)::text, 'UTF8')), 'hex')),
    1, 'consent proof is kept with the user id hashed'
);
SELECT is(
    (SELECT count(*)::int FROM billing.transaction_archive WHERE user_hash = encode(sha256(convert_to(pg_temp.u(3)::text, 'UTF8')), 'hex')),
    1, 'payment proof is kept with the user id hashed'
);
SELECT is((SELECT count(*)::int FROM privacy.deletion_log WHERE user_hash = encode(sha256(convert_to(pg_temp.u(3)::text, 'UTF8')), 'hex')),
    1, 'a hashed deletion log is written');

-- Catalog scan: no uuid / text / jsonb column anywhere still holds the id, email or name.
CREATE TEMP TABLE leftovers (where_found text);
DO $$
DECLARE col record; hit boolean;
BEGIN
    FOR col IN
        SELECT n.nspname, c.relname, a.attname, format_type(a.atttypid, NULL) AS t, tb.typbasetype
        FROM pg_attribute AS a
        JOIN pg_class AS c ON c.oid = a.attrelid
        JOIN pg_namespace AS n ON n.oid = c.relnamespace
        JOIN pg_type AS tb ON tb.oid = a.atttypid
        WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND a.attnum > 0 AND NOT a.attisdropped
          AND n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')
          AND (a.atttypid IN ('uuid'::regtype, 'jsonb'::regtype, 'text'::regtype)
               OR tb.typbasetype IN ('text'::regtype, 'uuid'::regtype))
    LOOP
        EXECUTE format(
            'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I::text LIKE ANY (ARRAY[%L, %L, %L]))',
            col.nspname, col.relname, col.attname,
            '%' || pg_temp.u(3)::text || '%', '%pv3@example.test%', '%Privacy Person3%'
        ) INTO hit;
        IF hit THEN
            INSERT INTO leftovers VALUES (col.nspname || '.' || col.relname || '.' || col.attname);
        END IF;
    END LOOP;
END $$;
SELECT is((SELECT array_agg(where_found ORDER BY 1) FROM leftovers), NULL, 'no trace of the user remains anywhere');

SELECT * FROM finish();
ROLLBACK;
