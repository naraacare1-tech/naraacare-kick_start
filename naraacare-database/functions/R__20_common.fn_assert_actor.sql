-- Object-level authorisation (doc 07 SEC-1.5, SEC-4.4): every function that takes p_user_id calls
-- this first. A mismatch raises 42501 with DETAIL NOT_FOUND; the API answers 404, never 403, so
-- callers cannot probe which ids exist.
CREATE OR REPLACE FUNCTION common.fn_assert_actor(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF p_user_id IS NULL OR p_user_id IS DISTINCT FROM common.fn_current_user_id() THEN
        RAISE EXCEPTION 'user does not match the authenticated actor'
            USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;
END
$$;

COMMENT ON FUNCTION common.fn_assert_actor(uuid) IS 'Raises 42501 unless p_user_id is the transaction actor (app.user_id)';
REVOKE ALL ON FUNCTION common.fn_assert_actor(uuid) FROM public;
GRANT EXECUTE ON FUNCTION common.fn_assert_actor(uuid) TO api_definer;
