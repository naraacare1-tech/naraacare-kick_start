-- BEFORE UPDATE triggers keeping the +STD columns honest (doc 05 section 1). Attached to every table
-- with an updated_at column by triggers/R__50_triggers_updated_at.sql; tests/110 checks coverage.
CREATE OR REPLACE FUNCTION common.trg_fn_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION common.trg_fn_set_updated_at() IS 'Trigger: updated_at = now()';
REVOKE ALL ON FUNCTION common.trg_fn_set_updated_at() FROM public;

-- Tables that also carry updated_by record the transaction actor (app.user_id) when there is one;
-- maintenance jobs without an actor keep whatever the statement set.
CREATE OR REPLACE FUNCTION common.trg_fn_set_updated_at_by()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    NEW.updated_at := now();
    NEW.updated_by := coalesce(common.current_user_id(), NEW.updated_by);
    RETURN NEW;
END
$$;

COMMENT ON FUNCTION common.trg_fn_set_updated_at_by() IS 'Trigger: updated_at = now(), updated_by = app.user_id when set';
REVOKE ALL ON FUNCTION common.trg_fn_set_updated_at_by() FROM public;
