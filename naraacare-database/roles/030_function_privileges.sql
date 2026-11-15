-- Function ownership and hardening (Session 03, doc 05 section 7, doc 07 SEC-4.3/4.7/7.1).

-- API functions are created by Flyway as api_definer (SET LOCAL ROLE api_definer in each R__ script),
-- which needs CREATE on their schemas. api_definer cannot log in and only runs our own function
-- bodies, which contain no dynamic SQL, so this adds no DDL reachable from the API.
GRANT CREATE ON SCHEMA auth, app, billing, ref, privacy, audit, nutrition, hydration, activity, notify, sleep TO api_definer;
-- pg_trgm (food search, voice matching) lives in schema public: USAGE only, no CREATE (V017).
GRANT USAGE ON SCHEMA public TO api_definer;

-- Consent history is append-only (SEC-7.1): the API role may only insert.
REVOKE UPDATE, DELETE ON privacy.consent_record FROM api_definer;

-- Audit trail: the API role can neither read nor alter it. change_log is written by the
-- audit.trg_fn_audit_row trigger (SECURITY DEFINER, owner migration_owner); security_event only by
-- audit.pr_log_security_event, which needs INSERT.
REVOKE ALL ON audit.change_log FROM api_definer;
REVOKE SELECT, UPDATE, DELETE ON audit.security_event FROM api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA audit
REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLES FROM api_definer;

-- Existing audit partitions (V012) got the old default privileges; align them with their parents.
DO $audit_partitions$
DECLARE
    p record;
BEGIN
    FOR p IN
        SELECT c.oid::regclass AS rel
        FROM pg_inherits AS i
        INNER JOIN pg_class AS c ON c.oid = i.inhrelid
        WHERE i.inhparent IN ('audit.change_log'::regclass, 'audit.security_event'::regclass)
        ORDER BY 1::text
    LOOP
        EXECUTE format('REVOKE ALL ON %s FROM api_definer', p.rel);
    END LOOP;
END
$audit_partitions$;
