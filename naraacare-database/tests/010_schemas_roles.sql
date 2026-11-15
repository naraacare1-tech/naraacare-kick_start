-- Schemas, roles and privileges (doc 05 sections 2 and 7).
BEGIN;
SELECT no_plan();

-- Schemas
SELECT has_schema(s, 'schema ' || s || ' exists')
FROM unnest(ARRAY[
    'common', 'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
    'billing', 'notify', 'privacy', 'audit', 'ops'
]) AS s;

-- Roles and their attributes
SELECT has_role(r, 'role ' || r || ' exists')
FROM unnest(ARRAY['migration_owner', 'api_definer', 'app_rw', 'app_worker', 'app_readonly', 'reporting']) AS r;

SELECT is(
    (
        SELECT count(*)::int FROM pg_roles
        WHERE
            rolname IN ('migration_owner', 'api_definer', 'app_rw', 'app_worker', 'app_readonly', 'reporting')
            AND (rolsuper OR rolbypassrls OR rolcreatedb)
    ),
    0,
    'no application role is superuser, can bypass RLS or create databases'
);
SELECT ok(NOT (
    SELECT rolcanlogin FROM pg_roles
    WHERE rolname = 'api_definer'
), 'api_definer cannot log in');
SELECT ok((
    SELECT rolcanlogin FROM pg_roles
    WHERE rolname = 'app_rw'
), 'app_rw can log in');
SELECT ok(NOT (
    SELECT rolcreaterole FROM pg_roles
    WHERE rolname = 'app_rw'
), 'app_rw cannot create roles');

-- Table privileges: app roles have NONE on any table (functions only, from Session 03)
SELECT is(
    (
        SELECT count(*)::int
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        CROSS JOIN unnest(ARRAY['app_rw', 'app_worker', 'app_readonly', 'reporting']) AS r (role_name)
        WHERE n.nspname IN (
            'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND c.relkind IN ('r', 'p', 'v', 'm')
        AND has_table_privilege(r.role_name, c.oid, 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
    ),
    0,
    'app_rw / app_worker / app_readonly / reporting have no table privileges at all'
);

-- api_definer has DML on every top-level table
SELECT is(
    (
        SELECT count(*)::int
        FROM pg_class AS c
        INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname IN (
            'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND c.relkind IN ('r', 'p')
        AND NOT c.relispartition
        AND n.nspname || '.' || c.relname NOT IN ('audit.change_log', 'audit.security_event', 'privacy.consent_record')
        AND NOT (
            has_table_privilege('api_definer', c.oid, 'SELECT')
            AND has_table_privilege('api_definer', c.oid, 'INSERT')
            AND has_table_privilege('api_definer', c.oid, 'UPDATE')
            AND has_table_privilege('api_definer', c.oid, 'DELETE')
        )
    ),
    0,
    'api_definer has SELECT/INSERT/UPDATE/DELETE on every table except the audit trail and consent history'
);

-- Session 03 hardening (V014): audit trail unreadable and unalterable, consent history insert-only.
SELECT ok(
    NOT has_table_privilege('api_definer', 'audit.change_log', 'SELECT, INSERT, UPDATE, DELETE'),
    'api_definer has no privilege on audit.change_log (written only by the audit trigger)'
);
SELECT ok(
    has_table_privilege('api_definer', 'audit.security_event', 'INSERT')
    AND NOT has_table_privilege('api_definer', 'audit.security_event', 'SELECT, UPDATE, DELETE'),
    'api_definer may only INSERT into audit.security_event'
);
SELECT ok(
    has_table_privilege('api_definer', 'privacy.consent_record', 'SELECT, INSERT')
    AND NOT has_table_privilege('api_definer', 'privacy.consent_record', 'UPDATE, DELETE'),
    'api_definer cannot UPDATE or DELETE consent records'
);
SELECT is(
    (
        SELECT count(*)::int
        FROM pg_inherits AS i
        INNER JOIN pg_class AS c ON c.oid = i.inhrelid
        WHERE
            i.inhparent IN ('audit.change_log'::regclass, 'audit.security_event'::regclass)
            AND has_table_privilege('api_definer', c.oid, 'SELECT, UPDATE, DELETE')
    ),
    0,
    'api_definer cannot read or alter audit partitions directly'
);
SELECT ok(
    NOT has_table_privilege('api_definer', 'auth.user_account', 'TRUNCATE'),
    'api_definer cannot TRUNCATE'
);

-- Nobody can create objects in public
SELECT ok(NOT has_schema_privilege('public', 'public', 'CREATE'), 'PUBLIC cannot create in schema public');

-- No function in our schemas is executable by PUBLIC
SELECT is(
    (
        SELECT count(*)::int
        FROM pg_proc AS p
        INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname IN (
            'common', 'auth', 'app', 'ref', 'activity', 'nutrition', 'hydration', 'sleep',
            'billing', 'notify', 'privacy', 'audit', 'ops'
        )
        AND has_function_privilege('public', p.oid, 'EXECUTE')
    ),
    0,
    'no function is executable by PUBLIC'
);

-- common.current_user_id()
SELECT is(common.current_user_id(), NULL::uuid, 'current_user_id() is NULL when app.user_id is unset');
SELECT set_config('app.user_id', '', TRUE);
SELECT is(common.current_user_id(), NULL::uuid, 'current_user_id() is NULL when app.user_id is empty');
SELECT set_config('app.user_id', '0192f000-0000-7000-8000-0000000000aa', TRUE);
SELECT is(
    common.current_user_id(), '0192f000-0000-7000-8000-0000000000aa'::uuid,
    'current_user_id() returns the transaction-local app.user_id'
);

SELECT * FROM finish();
ROLLBACK;
