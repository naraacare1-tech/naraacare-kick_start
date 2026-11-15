-- Upgrade a password hash after a successful sign-in when the Argon2id parameters have changed
-- (doc 07 SEC-1.1). Unlike auth.pr_set_password it does not touch the password history or revoke
-- sessions: the password itself is unchanged. Compare-and-swap on the old hash, so a password change
-- that lands in between is never overwritten. The API sets app.user_id to the signed-in user first.
-- o_updated: true when the hash was replaced.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_rehash_password(
    p_user_id uuid,
    p_old_hash common.argon2_hash,
    p_new_hash common.argon2_hash,
    INOUT o_updated boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE auth.user_account
    SET password_hash = p_new_hash
    WHERE id = p_user_id AND password_hash = p_old_hash;
    o_updated := FOUND;
END
$$;

COMMENT ON PROCEDURE auth.pr_rehash_password (uuid, common.argon2_hash, common.argon2_hash, boolean) IS
'Replace a password hash made with old Argon2id parameters (same password; no history, no revocation)';
REVOKE ALL ON PROCEDURE auth.pr_rehash_password(uuid, common.argon2_hash, common.argon2_hash, boolean)
FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_rehash_password(uuid, common.argon2_hash, common.argon2_hash, boolean)
TO app_rw;
