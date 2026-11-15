-- Refresh-token lookup by SHA-256 hash (e.g. to find the family on logout). Rotation itself is done
-- atomically by auth.pr_rotate_refresh_token; this function never changes state.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION auth.fn_refresh_token_lookup(p_token_hash common.blind_index)
RETURNS TABLE (
    token_id uuid,
    user_id uuid,
    family_id uuid,
    expires_at timestamptz,
    used_at timestamptz,
    revoked_at timestamptz,
    is_usable boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        t.id, t.user_id, t.family_id, t.expires_at, t.used_at, t.revoked_at,
        (t.used_at IS NULL AND t.revoked_at IS NULL AND t.expires_at > now())
    FROM auth.refresh_token AS t
    WHERE t.token_hash = p_token_hash
$$;

COMMENT ON FUNCTION auth.fn_refresh_token_lookup(common.blind_index) IS
'Read-only refresh-token lookup by hash (family, state)';
REVOKE ALL ON FUNCTION auth.fn_refresh_token_lookup(common.blind_index) FROM public;
GRANT EXECUTE ON FUNCTION auth.fn_refresh_token_lookup(common.blind_index) TO app_rw;
