-- Row audit trigger (doc 07 SEC-4.7). Writes who changed what to audit.change_log.
--   * actor = app.user_id, request = app.request_id (both set per transaction by the API)
--   * UPDATE stores only the changed columns; a change touching only updated_at/updated_by is skipped
--   * hashes are never stored: any column ending in _hash (password, refresh token) is replaced by
--     "[redacted]" (the column name is still listed in changed_columns)
-- SECURITY DEFINER owned by migration_owner, so the API role needs no privilege on audit.change_log
-- (it can neither read nor alter the audit trail). TG_ARGV = primary-key column names (default id).
CREATE OR REPLACE FUNCTION audit.trg_fn_audit_row()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_old jsonb;
    v_new jsonb;
    v_row jsonb;
    v_changed text[];
    v_pk text;
    v_request text := current_setting('app.request_id', true);
    i integer;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_old := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_new := to_jsonb(NEW);
    END IF;
    v_row := coalesce(v_new, v_old);

    IF TG_OP = 'UPDATE' THEN
        SELECT array_agg(n.key ORDER BY n.key) INTO v_changed
        FROM jsonb_each(v_new) AS n
        WHERE n.value IS DISTINCT FROM v_old -> n.key
          AND n.key NOT IN ('updated_at', 'updated_by');
        IF v_changed IS NULL THEN
            RETURN NULL;
        END IF;
        SELECT jsonb_object_agg(key, value) INTO v_old FROM jsonb_each(v_old) WHERE key = ANY (v_changed);
        SELECT jsonb_object_agg(key, value) INTO v_new FROM jsonb_each(v_new) WHERE key = ANY (v_changed);
    ELSE
        SELECT array_agg(k ORDER BY k) INTO v_changed FROM jsonb_object_keys(v_row) AS k;
    END IF;

    SELECT jsonb_object_agg(
        key, CASE WHEN key ~ '_hash$' THEN to_jsonb('[redacted]'::text) ELSE value END
    ) INTO v_old FROM jsonb_each(v_old);
    SELECT jsonb_object_agg(
        key, CASE WHEN key ~ '_hash$' THEN to_jsonb('[redacted]'::text) ELSE value END
    ) INTO v_new FROM jsonb_each(v_new);

    IF TG_NARGS = 0 THEN
        v_pk := v_row ->> 'id';
    ELSE
        FOR i IN 0 .. TG_NARGS - 1 LOOP
            v_pk := concat_ws(':', v_pk, v_row ->> TG_ARGV[i]);
        END LOOP;
    END IF;

    INSERT INTO audit.change_log (
        schema_name, table_name, row_pk, action, actor_user_id, db_role, request_id,
        changed_columns, old_values, new_values
    ) VALUES (
        TG_TABLE_SCHEMA, TG_TABLE_NAME, v_pk, lower(TG_OP), common.current_user_id(), session_user,
        CASE WHEN v_request ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN v_request::uuid END,
        v_changed, v_old, v_new
    );
    RETURN NULL;
END
$$;

COMMENT ON FUNCTION audit.trg_fn_audit_row() IS
'AFTER ROW trigger writing audit.change_log with actor, request id and redacted values (SEC-4.7)';
REVOKE ALL ON FUNCTION audit.trg_fn_audit_row() FROM public;
