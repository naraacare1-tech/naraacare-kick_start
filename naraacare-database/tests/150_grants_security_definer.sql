-- Function privileges, ownership and SECURITY DEFINER hygiene (doc 07 SEC-4.1, SEC-4.3).
BEGIN;
SELECT no_plan();

CREATE TEMP VIEW our_routines AS
SELECT
    p.oid,
    n.nspname AS schema_name,
    p.proname AS routine_name,
    p.oid::regprocedure::text AS signature,
    p.prokind,
    p.prosecdef,
    p.proconfig,
    pg_get_userbyid(p.proowner) AS owner,
    p.prorettype = 'trigger'::regtype AS is_trigger
FROM pg_proc AS p
INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname IN (
    'common', 'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
    'billing', 'notify', 'privacy', 'audit', 'ops'
);

-- Every SECURITY DEFINER routine pins search_path (SEC-4.3)
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE prosecdef AND NOT coalesce('search_path=pg_catalog, pg_temp' = any(proconfig), FALSE)
    ),
    NULL,
    'every SECURITY DEFINER routine has SET search_path = pg_catalog, pg_temp'
);
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE NOT coalesce('search_path=pg_catalog, pg_temp' = any(proconfig), FALSE)
    ),
    NULL,
    'in fact every routine pins search_path'
);

-- Ownership: API routines belong to api_definer (subject to RLS); a short allow-list runs as the table
-- owner because it must cross users (maintenance, username availability, audit trigger).
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE
            prosecdef AND owner <> 'api_definer'
            AND NOT (
                schema_name = 'ops'
                OR signature IN ('app.fn_username_available(common.username)', 'audit.trg_fn_audit_row()')
            )
    ),
    NULL,
    'SECURITY DEFINER routines are owned by api_definer, except the owner-run allow-list'
);
SELECT is(
    (
        SELECT array_agg(DISTINCT owner) FROM our_routines
        WHERE schema_name = 'ops'
    ),
    ARRAY['migration_owner']::name[],
    'ops maintenance routines are owned by migration_owner'
);

-- PUBLIC can execute nothing
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE has_function_privilege('public', oid, 'EXECUTE')
    ),
    NULL,
    'no routine is executable by PUBLIC'
);

-- app_rw: the API routines, nothing internal, nothing from ops
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE
            has_function_privilege('app_rw', oid, 'EXECUTE')
            AND (schema_name IN ('ops', 'common') OR is_trigger OR routine_name = 'pr_upsert_target_snapshot')
            AND signature <> 'ops.fn_ping()'
    ),
    NULL,
    'app_rw cannot execute ops (except the fn_ping probe), common helpers, trigger functions or internal procedures'
);
SELECT
    ok(
        has_function_privilege('app_rw', r, 'EXECUTE'), 'app_rw can execute ' || r
    )
FROM unnest(ARRAY[
    'auth.pr_create_account(common.email, common.argon2_hash, uuid, common.otp_code, uuid, uuid, text, integer)',
    'auth.pr_verify_otp(uuid, boolean, uuid, text, integer, text)',
    'auth.pr_rotate_refresh_token(common.blind_index, common.blind_index, uuid, uuid, uuid, uuid, timestamp with time zone, text, text)',
    'auth.fn_find_account_by_email(common.email)',
    'app.fn_get_profile(uuid)',
    'app.pr_set_username(uuid, common.username)',
    'billing.fn_current_entitlement(uuid)',
    'ref.fn_bootstrap()',
    'ops.fn_ping()',
    'audit.pr_log_security_event(common.code, uuid, inet, uuid, common.code, jsonb)'
]) AS r;
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE
            has_function_privilege('app_rw', oid, 'EXECUTE')
            AND NOT prosecdef
            AND signature <> 'ops.fn_ping()'
    ),
    NULL,
    'everything app_rw can call is a SECURITY DEFINER entry point, except the table-free fn_ping probe'
);

-- app_worker: ops maintenance
SELECT
    ok(
        has_function_privilege('app_worker', signature, 'EXECUTE'), 'app_worker can execute ' || signature
    )
FROM our_routines
WHERE schema_name = 'ops';

-- app_readonly: only read-only (STABLE/IMMUTABLE) functions, never procedures
SELECT is(
    (
        SELECT array_agg(o.signature ORDER BY o.signature)
        FROM our_routines AS o
        INNER JOIN pg_proc AS p ON p.oid = o.oid
        WHERE
            has_function_privilege('app_readonly', o.oid, 'EXECUTE')
            AND (o.prokind <> 'f' OR p.provolatile = 'v')
    ),
    NULL,
    'app_readonly can only execute read-only functions'
);
SELECT is(
    (
        SELECT array_agg(signature ORDER BY signature) FROM our_routines
        WHERE has_function_privilege('reporting', oid, 'EXECUTE')
    ),
    NULL,
    'reporting cannot execute any routine'
);

-- No dynamic SQL outside ops (SEC-4.1). Repeatable trigger scripts run DDL in DO blocks, not routines.
SELECT is(
    (
        SELECT array_agg(o.signature ORDER BY o.signature)
        FROM our_routines AS o
        INNER JOIN pg_proc AS p ON p.oid = o.oid
        WHERE o.schema_name <> 'ops' AND p.prosrc ~* '\mEXECUTE\M'
    ),
    NULL,
    'no EXECUTE (dynamic SQL) in any routine outside ops'
);

-- Realistic path: the API login role calls a procedure and the actor check holds.
GRANT USAGE ON SCHEMA public TO app_rw;
INSERT INTO auth.user_account (id, email, status) VALUES
('0192f000-0000-7000-8000-0000000000f1', 'uf1@example.test', 'active'),
('0192f000-0000-7000-8000-0000000000f2', 'uf2@example.test', 'active');
SET LOCAL ROLE app_rw;
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000000f1', TRUE);
SELECT throws_ok('SELECT count(*) FROM auth.user_account', '42501', NULL, 'app_rw cannot read tables directly');
SELECT is(
    (SELECT user_id FROM app.fn_get_profile('0192f000-0000-7000-8000-0000000000f1')),
    '0192f000-0000-7000-8000-0000000000f1'::uuid,
    'app_rw reads its own profile through the function'
);
SELECT throws_ok(
    $$SELECT * FROM app.fn_get_profile('0192f000-0000-7000-8000-0000000000f2')$$,
    '42501', NULL, 'app_rw cannot read another user''s profile (actor mismatch -> 404)'
);
SELECT throws_ok(
    'CALL ops.pr_ensure_partitions(NULL, NULL, NULL)', '42501', NULL, 'app_rw cannot run maintenance'
);
SELECT throws_ok(
    $$CALL app.pr_upsert_target_snapshot('0192f000-0000-7000-8000-0000000000f1', current_date, '{}')$$,
    '42501', NULL, 'app_rw cannot call internal procedures'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
