-- Audit trail, security events and append-only consent (doc 07 SEC-4.7, section 4.4, SEC-7.1).
BEGIN;
SELECT no_plan();

\ir payloads/xss_payloads.psql

-- Audit triggers on every sensitive table
SELECT is(
    (
        SELECT array_agg(n.nspname || '.' || c.relname ORDER BY 1)
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE
            c.relkind IN ('r', 'p')
            AND NOT c.relispartition
            AND (
                n.nspname IN ('ref', 'privacy')
                OR n.nspname || '.' || c.relname IN (
                    'auth.user_account', 'app.user_profile', 'billing.subscription',
                    'billing.entitlement_grant', 'nutrition.food_item'
                )
            )
            AND NOT EXISTS (
                SELECT 1 FROM pg_trigger AS t
                WHERE t.tgrelid = c.oid AND t.tgname = 'trg_audit_row' AND NOT t.tgisinternal
            )
    ),
    NULL,
    'audit trigger on auth.user_account, app.user_profile, billing grants/subscriptions, food items, ref.*, privacy.*'
);

-- INSERT: secrets redacted
SELECT set_config('app.request_id', '0192f000-0000-7000-8000-00000000f001', TRUE);
INSERT INTO auth.user_account (id, email, password_hash, status) VALUES (
    '0192f000-0000-7000-8000-0000000000c1', 'uc1@example.test',
    '$argon2id$v=19$m=65536,t=3,p=2$c2FsdHNhbHQ$cGFzc3dvcmRoYXNo', 'active'
);
SELECT is(
    (
        SELECT ARRAY[new_values ->> 'email', new_values ->> 'password_hash']
        FROM audit.change_log
        WHERE table_name = 'user_account' AND row_pk = '0192f000-0000-7000-8000-0000000000c1' AND action = 'insert'
    ),
    ARRAY['uc1@example.test', '[redacted]'],
    'the password hash is redacted in the audit row; the email is kept in plain text'
);
SELECT ok(
    (
        SELECT changed_columns @> ARRAY['email', 'password_hash']::common.code[]
        FROM audit.change_log
        WHERE row_pk = '0192f000-0000-7000-8000-0000000000c1' AND action = 'insert'
    ),
    'redacted columns are still listed in changed_columns'
);
SELECT is(
    (
        SELECT request_id FROM audit.change_log
        WHERE row_pk = '0192f000-0000-7000-8000-0000000000c1'
    ),
    '0192f000-0000-7000-8000-00000000f001'::uuid,
    'request_id comes from app.request_id'
);

-- UPDATE: only changed columns, actor recorded
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000000c1', TRUE);
INSERT INTO app.user_profile (user_id, height_cm) VALUES ('0192f000-0000-7000-8000-0000000000c1', 170);
UPDATE app.user_profile SET height_cm = 171.5, full_name = 'Asha Rao'
WHERE user_id = '0192f000-0000-7000-8000-0000000000c1';
SELECT results_eq(
    $$SELECT changed_columns::text[], old_values ->> 'height_cm', new_values ->> 'height_cm',
             new_values ->> 'full_name', actor_user_id
      FROM audit.change_log
      WHERE table_name = 'user_profile' AND action = 'update'$$,
    $$VALUES (array['full_name', 'height_cm'], '170.0', '171.5', 'Asha Rao',
              '0192f000-0000-7000-8000-0000000000c1'::uuid)$$,
    'UPDATE audit row: only the changed columns, actor from app.user_id'
);
UPDATE app.user_profile SET updated_at = now() - interval '1 day'
WHERE user_id = '0192f000-0000-7000-8000-0000000000c1';
SELECT is(
    (
        SELECT count(*)::int FROM audit.change_log
        WHERE table_name = 'user_profile' AND action = 'update'
    ),
    1,
    'an UPDATE that only touches updated_at is not audited'
);

-- Composite primary keys and invalid request ids
SELECT set_config('app.request_id', 'not-a-uuid', TRUE);
UPDATE ref.feature_entitlement SET limit_value = 5
WHERE tier_code = 'standard' AND feature_code = 'meal_logs_per_day';
SELECT results_eq(
    $$SELECT row_pk::text, request_id FROM audit.change_log WHERE table_name = 'feature_entitlement'$$,
    $$VALUES ('standard:meal_logs_per_day', NULL::uuid)$$,
    'composite key recorded as a:b; a malformed app.request_id is ignored, never breaks the write'
);

-- No secret material anywhere in the audit log
SELECT is(
    (
        SELECT count(*)::int FROM audit.change_log
        WHERE coalesce(old_values::text, '') || coalesce(new_values::text, '') ~ '(argon2id|\\\\x)'
    ),
    0,
    'audit log contains no Argon2 hashes and no raw bytea (token digests)'
);

-- Security events: details limited to numbers, booleans and codes
CALL audit.pr_log_security_event(
    'validation_rejected', NULL, inet '203.0.113.7', NULL, 'full_name',
    '{"rule": "safe_text.no_markup", "length": 12, "blocked": true}'
);
SELECT results_eq(
    $$SELECT event_type::text, field_name::text, details FROM audit.security_event WHERE field_name = 'full_name'$$,
    $$VALUES ('validation_rejected', 'full_name', '{"rule": "safe_text.no_markup", "length": 12, "blocked": true}'::jsonb)$$,
    'security event written'
);
SELECT throws_ok(
    $$CALL audit.pr_log_security_event('validation_rejected', NULL, NULL, NULL, NULL, '{"value": "Hello World"}')$$,
    '22023', NULL, 'free text in details is rejected'
);
SELECT throws_ok(
    $$CALL audit.pr_log_security_event('validation_rejected', NULL, NULL, NULL, NULL, '{"nested": {"a": 1}}')$$,
    '22023', NULL, 'nested objects in details are rejected'
);
SELECT throws_ok(
    $$CALL audit.pr_log_security_event('validation_rejected', NULL, NULL, NULL, NULL, '[1, 2]')$$,
    '22023', NULL, 'non-object details are rejected'
);
SELECT throws_ok(
    $$CALL audit.pr_log_security_event('not_an_event', NULL, NULL, NULL, NULL, '{}')$$,
    '23514', NULL, 'unknown event types are rejected by the table CHECK'
);
DO $payloads$
DECLARE
    r record;
    v_stored integer := 0;
BEGIN
    FOR r IN SELECT payload FROM test_payloads LOOP
        BEGIN
            CALL audit.pr_log_security_event(
                'validation_rejected', NULL, NULL, NULL, NULL, jsonb_build_object('value', r.payload)
            );
            v_stored := v_stored + 1;
        EXCEPTION WHEN invalid_parameter_value THEN
            NULL;
        END;
    END LOOP;
    CREATE TEMP TABLE event_payload_result AS SELECT v_stored AS stored;
END
$payloads$;
SELECT is((SELECT stored FROM event_payload_result), 0, 'no payload can be stored in security event details');

-- Consent history is append-only
INSERT INTO privacy.consent_record (user_id, purpose, policy_version, granted)
VALUES ('0192f000-0000-7000-8000-0000000000c1', 'health_data', '0.0-draft', TRUE);
SELECT throws_ok(
    $$UPDATE privacy.consent_record SET granted = FALSE WHERE user_id = '0192f000-0000-7000-8000-0000000000c1'$$,
    '42501', NULL, 'consent records cannot be updated (even by a superuser session)'
);
SELECT throws_ok(
    $$DELETE FROM privacy.consent_record WHERE user_id = '0192f000-0000-7000-8000-0000000000c1'$$,
    '42501', NULL, 'consent records cannot be deleted directly'
);
SELECT lives_ok(
    $$DELETE FROM auth.user_account WHERE id = '0192f000-0000-7000-8000-0000000000c1'$$,
    'account deletion still cascades (FK actions run as the table owner)'
);
SELECT is(
    (
        SELECT count(*)::int FROM audit.change_log
        WHERE table_name = 'consent_record' AND action = 'delete'
    ),
    1,
    'the cascaded consent deletion is itself audited'
);

SELECT * FROM finish();
ROLLBACK;
