-- Keep the Sign in with Apple refresh token (plain text) on the identity link (doc 07 SEC-1.4).
-- Apple requires apps to revoke the user's tokens when the account is deleted; the API obtains this
-- token by exchanging the authorization_code at sign-in, and Session 15 uses it on deletion.
-- Only the actor's own link can be updated. o_updated: true when a link was found.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_store_provider_token(
    p_user_id uuid,
    p_provider common.code,
    p_subject common.opaque_ref,
    p_token common.opaque_token,
    INOUT o_updated boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE auth.identity_link
    SET provider_refresh_token = p_token
    WHERE user_id = p_user_id
      AND provider = p_provider
      AND subject = p_subject
      AND deleted_at IS NULL;
    o_updated := FOUND;
END
$$;

COMMENT ON PROCEDURE auth.pr_store_provider_token (
    uuid, common.code, common.opaque_ref, common.opaque_token, boolean
) IS 'Store the provider refresh token on the actor''s identity link (Apple revocation)';
REVOKE ALL ON PROCEDURE auth.pr_store_provider_token(
    uuid, common.code, common.opaque_ref, common.opaque_token, boolean
) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_store_provider_token(
    uuid, common.code, common.opaque_ref, common.opaque_token, boolean
) TO app_rw;
