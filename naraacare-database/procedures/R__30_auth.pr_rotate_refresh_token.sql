-- POST /auth/token/refresh (doc 07 SEC-1.2, threat T3). The presented token is the credential, so there
-- is no actor check. Under a row lock:
--   * unknown hash                       -> invalid
--   * already used or revoked            -> REUSE: every live token of the family is revoked
--                                           (reuse_detected), a refresh_reuse security event is logged,
--                                           the user must sign in again
--   * presented from another installation -> treated as reuse (tokens are bound to the installation)
--   * expired                            -> expired (nothing to revoke)
--   * account no longer active           -> account_inactive (family revoked). A temporary lockout
--                                           (locked_until) does not end existing sessions: it only
--                                           blocks password guessing
--   * otherwise the token is marked used and replaced by a child in the same family, 60 days from now
-- Outcomes are returned, not raised, so the revocations and the event are committed.
-- o_status: ok | invalid | reuse_detected | expired | account_inactive
-- Note: strict reuse detection means a client retrying the same refresh after a network drop is
-- signed out; the app serialises refresh calls to avoid that.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_rotate_refresh_token(
    p_token_hash common.blind_index,
    p_new_token_hash common.blind_index,
    p_installation_id uuid,
    INOUT o_user_id uuid DEFAULT NULL,
    INOUT o_family_id uuid DEFAULT NULL,
    INOUT o_token_id uuid DEFAULT NULL,
    INOUT o_expires_at timestamptz DEFAULT NULL,
    INOUT o_role text DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_token auth.refresh_token%ROWTYPE;
    v_account auth.user_account%ROWTYPE;
BEGIN
    o_token_id := NULL;
    o_expires_at := NULL;
    o_role := NULL;
    SELECT * INTO v_token FROM auth.refresh_token WHERE token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND THEN
        o_user_id := NULL;
        o_family_id := NULL;
        o_status := 'invalid';
        RETURN;
    END IF;
    o_user_id := v_token.user_id;
    o_family_id := v_token.family_id;

    IF v_token.used_at IS NOT NULL OR v_token.revoked_at IS NOT NULL
       OR v_token.installation_id IS DISTINCT FROM p_installation_id THEN
        UPDATE auth.refresh_token
        SET revoked_at = now(), revoked_reason = 'reuse_detected'
        WHERE family_id = v_token.family_id AND revoked_at IS NULL;
        CALL audit.pr_log_security_event(
            'refresh_reuse', v_token.user_id, NULL, NULL, NULL,
            jsonb_build_object(
                'installation_mismatch', v_token.installation_id IS DISTINCT FROM p_installation_id
            )
        );
        o_status := 'reuse_detected';
        RETURN;
    END IF;

    SELECT * INTO v_account FROM auth.user_account WHERE id = v_token.user_id;
    IF v_token.expires_at <= now() THEN
        o_status := 'expired';
        RETURN;
    END IF;
    IF v_account.status <> 'active' THEN
        UPDATE auth.refresh_token
        SET revoked_at = now(), revoked_reason = 'admin'
        WHERE family_id = v_token.family_id AND revoked_at IS NULL;
        o_status := 'account_inactive';
        RETURN;
    END IF;

    UPDATE auth.refresh_token
    SET used_at = now(), revoked_at = now(), revoked_reason = 'rotated'
    WHERE id = v_token.id;
    INSERT INTO auth.refresh_token (user_id, family_id, parent_id, token_hash, installation_id, expires_at)
    VALUES (v_token.user_id, v_token.family_id, v_token.id, p_new_token_hash, p_installation_id, now() + interval '60 days')
    RETURNING id, expires_at INTO o_token_id, o_expires_at;
    o_role := v_account.role;
    o_status := 'ok';
END
$$;

COMMENT ON PROCEDURE auth.pr_rotate_refresh_token (
    common.blind_index, common.blind_index, uuid, uuid, uuid, uuid, timestamptz, text, text
) IS 'Rotate a refresh token; reuse or installation mismatch revokes the whole family (SEC-1.2)';
REVOKE ALL ON PROCEDURE auth.pr_rotate_refresh_token(
    common.blind_index, common.blind_index, uuid, uuid, uuid, uuid, timestamptz, text, text
) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_rotate_refresh_token(
    common.blind_index, common.blind_index, uuid, uuid, uuid, uuid, timestamptz, text, text
) TO app_rw;
