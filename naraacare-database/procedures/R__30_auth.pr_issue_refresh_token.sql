-- Issues a refresh token after a successful sign-in, OTP or OAuth (doc 07 SEC-1.2). The API generates
-- 256 random bits, returns them to the app once and passes only the SHA-256 here. p_family_id NULL
-- starts a new family (= one device session, the JWT "sid"). Expiry: 60 days, sliding on rotation.
-- The API sets app.user_id to the authenticated user before calling.
-- Errors: P0001 ACCOUNT_NOT_ACTIVE when the account cannot sign in.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_issue_refresh_token(
    p_user_id uuid,
    p_token_hash common.blind_index,
    p_installation_id uuid,
    INOUT o_token_id uuid DEFAULT NULL,
    INOUT o_family_id uuid DEFAULT NULL,
    INOUT o_expires_at timestamptz DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF NOT EXISTS (
        SELECT 1 FROM auth.user_account AS a
        WHERE a.id = p_user_id AND a.status = 'active' AND (a.locked_until IS NULL OR a.locked_until <= now())
    ) THEN
        RAISE EXCEPTION 'account cannot sign in' USING ERRCODE = 'P0001', DETAIL = 'ACCOUNT_NOT_ACTIVE';
    END IF;

    o_family_id := uuidv7();
    INSERT INTO auth.refresh_token (user_id, family_id, token_hash, installation_id, expires_at)
    VALUES (p_user_id, o_family_id, p_token_hash, p_installation_id, now() + interval '60 days')
    RETURNING id, expires_at INTO o_token_id, o_expires_at;
END
$$;

COMMENT ON PROCEDURE auth.pr_issue_refresh_token (uuid, common.blind_index, uuid, uuid, uuid, timestamptz) IS
'Start a refresh-token family (60-day expiry) for an active account';
REVOKE ALL ON PROCEDURE auth.pr_issue_refresh_token(uuid, common.blind_index, uuid, uuid, uuid, timestamptz)
FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_issue_refresh_token(uuid, common.blind_index, uuid, uuid, uuid, timestamptz)
TO app_rw;
