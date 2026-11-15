-- Actor of the current transaction. The API sets app.user_id with set_config(..., true) after
-- authenticating the request. Unlike common.current_user_id() (used by RLS policies, returns NULL),
-- this raises when no actor is set, so a function can never run "as nobody".
CREATE OR REPLACE FUNCTION common.fn_current_user_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_user_id uuid := common.current_user_id();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'no authenticated user in this transaction'
            USING ERRCODE = '42501', DETAIL = 'NOT_AUTHENTICATED';
    END IF;
    RETURN v_user_id;
END
$$;

COMMENT ON FUNCTION common.fn_current_user_id() IS 'app.user_id of the current transaction; raises 42501 when unset';
REVOKE ALL ON FUNCTION common.fn_current_user_id() FROM public;
GRANT EXECUTE ON FUNCTION common.fn_current_user_id() TO api_definer;
