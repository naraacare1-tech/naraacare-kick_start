-- Social sign-in lookup (doc 07 SEC-1.4): provider + subject -> account. Called after the
-- API has verified the Google/Apple token, before any actor exists.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_find_identity(p_provider common.code, p_subject common.opaque_ref)
RETURNS TABLE (
    user_id uuid,
    status common.code,
    role common.code,
    locked_until timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT a.id, a.status, a.role, a.locked_until
    FROM auth.identity_link AS i
    INNER JOIN auth.user_account AS a ON a.id = i.user_id
    WHERE i.provider = p_provider
      AND i.subject = p_subject
      AND i.deleted_at IS NULL
      AND a.status <> 'deleted'
$$;

COMMENT ON FUNCTION auth.fn_find_identity(common.code, common.opaque_ref) IS
'Pre-auth lookup of a Google/Apple identity link';
REVOKE ALL ON FUNCTION auth.fn_find_identity(common.code, common.opaque_ref) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_find_identity(common.code, common.opaque_ref) TO app_rw;
