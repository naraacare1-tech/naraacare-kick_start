-- Consent history is append-only (doc 07 SEC-7.1, threat T23). UPDATE and DELETE raise for every role
-- except migration_owner, which runs the retention/anonymisation job and owns the FK cascade from
-- auth.user_account (referential actions run as the table owner).
CREATE OR REPLACE FUNCTION privacy.trg_fn_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF current_user <> 'migration_owner' THEN
        RAISE EXCEPTION '%.% is append-only', TG_TABLE_SCHEMA, TG_TABLE_NAME
            USING ERRCODE = '42501', DETAIL = 'APPEND_ONLY';
    END IF;
    RETURN coalesce(NEW, OLD);
END
$$;

COMMENT ON FUNCTION privacy.trg_fn_append_only() IS 'BEFORE UPDATE/DELETE trigger: append-only tables (consent history)';
REVOKE ALL ON FUNCTION privacy.trg_fn_append_only() FROM public;
