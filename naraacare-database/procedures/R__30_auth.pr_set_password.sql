-- Password change or reset (doc 04 section 2.1, OQ-29). The API has already checked the candidate
-- against auth.fn_password_history (reuse -> 422 PASSWORD_REUSED) and hashed it with Argon2id.
-- Stores the hash, appends it to the history (keeping the newest 5), clears any lockout and revokes
-- every session except p_keep_family_id (change keeps the current device; reset keeps none).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_set_password(
    p_user_id uuid,
    p_password_hash common.argon2_hash,
    p_keep_family_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);

    UPDATE auth.user_account
    SET password_hash = p_password_hash, failed_login_count = 0, locked_until = NULL
    WHERE id = p_user_id AND status IN ('active', 'locked', 'pending_verification');
    IF NOT FOUND THEN
        RAISE EXCEPTION 'account not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;

    INSERT INTO auth.password_history (user_id, password_hash) VALUES (p_user_id, p_password_hash);
    DELETE FROM auth.password_history AS h
    WHERE h.user_id = p_user_id
      AND h.id NOT IN (
          SELECT k.id FROM auth.password_history AS k
          WHERE k.user_id = p_user_id
          ORDER BY k.created_at DESC, k.id DESC
          LIMIT 5
      );

    UPDATE auth.refresh_token
    SET revoked_at = now(), revoked_reason = 'password_change'
    WHERE user_id = p_user_id
      AND revoked_at IS NULL
      AND family_id IS DISTINCT FROM p_keep_family_id;
END
$$;

COMMENT ON PROCEDURE auth.pr_set_password (uuid, common.argon2_hash, uuid) IS
'Store a new password hash, keep 5 in history, revoke other sessions';
REVOKE ALL ON PROCEDURE auth.pr_set_password(uuid, common.argon2_hash, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_set_password(uuid, common.argon2_hash, uuid) TO app_rw;
