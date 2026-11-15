-- POST /devices and DELETE /devices/{installation_id} (doc 04 section 2.7, doc 07 SEC-6). A device is
-- bound to the caller (user from the token, never from the body) and keyed by its installation id.
-- The installation id and FCM token are stored in plain text.
--   * Register = upsert: a new token, platform or app version replaces the old; a revoked device
--     comes back. At most 10 active devices per user: the least recently seen ones are revoked.
--   * Revoke: the push token is wiped at once (logout, sign-out of all devices).
-- Errors: 42501 not the actor, 22023 invalid platform / app version (domains, CHECKs).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE notify.pr_register_device(
    p_user_id uuid,
    p_installation_id uuid,
    p_platform common.code,
    p_push_token common.opaque_token,
    p_app_version common.app_version,
    INOUT o_device_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_installation_id IS NULL OR p_platform IS NULL OR p_app_version IS NULL THEN
        RAISE EXCEPTION 'installation, platform and app version are required'
            USING ERRCODE = '22023', DETAIL = 'DEVICE_INVALID';
    END IF;

    INSERT INTO notify.device (user_id, installation_id, platform, push_token, app_version)
    VALUES (p_user_id, p_installation_id, p_platform, p_push_token, p_app_version)
    ON CONFLICT ON CONSTRAINT uq_device__user_installation DO UPDATE SET
        platform = excluded.platform,
        push_token = excluded.push_token,
        app_version = excluded.app_version,
        last_seen_at = now(),
        revoked_at = NULL,
        updated_at = now()
    RETURNING id INTO o_device_id;

    UPDATE notify.device AS d
    SET revoked_at = now(), push_token = NULL, updated_at = now()
    WHERE d.id IN (
        SELECT x.id FROM notify.device AS x
        WHERE x.user_id = p_user_id AND x.revoked_at IS NULL
        ORDER BY x.last_seen_at DESC, x.id DESC
        OFFSET 10
    );
END
$$;

COMMENT ON PROCEDURE notify.pr_register_device (uuid, uuid, common.code, common.opaque_token, common.app_version, uuid) IS
'Register or refresh the caller''s device (FCM token); at most 10 active devices';
REVOKE ALL ON PROCEDURE notify.pr_register_device(uuid, uuid, common.code, common.opaque_token, common.app_version, uuid)
FROM public;
GRANT EXECUTE ON PROCEDURE notify.pr_register_device(uuid, uuid, common.code, common.opaque_token, common.app_version, uuid)
TO app_rw;

CREATE OR REPLACE PROCEDURE notify.pr_revoke_device(
    p_user_id uuid,
    p_installation_id uuid,
    INOUT o_revoked boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE notify.device AS d
    SET revoked_at = coalesce(d.revoked_at, now()), push_token = NULL, updated_at = now()
    WHERE d.user_id = p_user_id AND d.installation_id = p_installation_id;
    o_revoked := FOUND;
END
$$;

COMMENT ON PROCEDURE notify.pr_revoke_device (uuid, uuid, boolean) IS
'Revoke the caller''s device and wipe its push token (idempotent)';
REVOKE ALL ON PROCEDURE notify.pr_revoke_device(uuid, uuid, boolean) FROM public;
GRANT EXECUTE ON PROCEDURE notify.pr_revoke_device(uuid, uuid, boolean) TO app_rw;
