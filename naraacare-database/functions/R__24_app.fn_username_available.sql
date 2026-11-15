-- GET /usernames/availability (doc 04 section 2.2). Usernames live in app.user_profile, which has RLS,
-- so an api_definer-owned function would only see the caller's own row. This function is therefore
-- owned by migration_owner (the table owner, exempt from RLS) and returns a single boolean, nothing
-- else about other users. It is on the short owner-run allow-list checked by tests/150.
-- The common.username parameter type rejects anything that is not a valid username (23514).
-- Uniqueness itself is enforced by uq_user_profile__username; this is only a UI hint.
CREATE OR REPLACE FUNCTION app.fn_username_available(p_username common.username)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_actor uuid := common.fn_current_user_id();
BEGIN
    RETURN NOT EXISTS (
        SELECT 1
        FROM app.user_profile AS p
        WHERE p.username = p_username
          AND p.deleted_at IS NULL
          AND p.user_id <> v_actor
    );
END
$$;

COMMENT ON FUNCTION app.fn_username_available(common.username) IS
'True when no other user holds the username (owner-run: crosses RLS, returns only a boolean)';
REVOKE ALL ON FUNCTION app.fn_username_available(common.username) FROM public;
GRANT EXECUTE ON FUNCTION app.fn_username_available(common.username) TO app_rw, app_readonly;
