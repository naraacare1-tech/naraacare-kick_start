-- First Google/Apple sign-in (doc 07 SEC-1.4). The API has verified the provider token and that the
-- provider marked the email as verified, so the account starts active with no password.
--   * identity already linked -> o_status existing (o_user_id = that account)
--   * an account with this email exists but is not linked -> link_required (OQ-30: the user must
--     prove the password once via POST /auth/oauth/link; silent linking would allow takeover
--     through a provider account that merely claims the email)
-- o_status: created | existing | link_required
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_create_oauth_account(
    p_provider common.code,
    p_subject common.opaque_ref,
    p_email common.email,
    p_installation_id uuid,
    INOUT o_user_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtextextended('auth.signup:' || p_email, 0));

    SELECT i.user_id INTO o_user_id
    FROM auth.identity_link AS i
    WHERE i.provider = p_provider AND i.subject = p_subject AND i.deleted_at IS NULL;
    IF FOUND THEN
        o_status := 'existing';
        RETURN;
    END IF;

    IF EXISTS (SELECT 1 FROM auth.user_account AS a WHERE a.email = p_email) THEN
        o_user_id := NULL;
        o_status := 'link_required';
        RETURN;
    END IF;

    INSERT INTO auth.user_account (email, status, email_verified_at, installation_id)
    VALUES (p_email, 'active', now(), p_installation_id)
    RETURNING id INTO o_user_id;
    INSERT INTO auth.identity_link (user_id, provider, subject, email)
    VALUES (o_user_id, p_provider, p_subject, p_email);
    o_status := 'created';
END
$$;

COMMENT ON PROCEDURE auth.pr_create_oauth_account (
    common.code, common.opaque_ref, common.email, uuid, uuid, text
) IS 'First social sign-in: created | existing | link_required (never links silently)';
REVOKE ALL ON PROCEDURE auth.pr_create_oauth_account(
    common.code, common.opaque_ref, common.email, uuid, uuid, text
) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_create_oauth_account(
    common.code, common.opaque_ref, common.email, uuid, uuid, text
) TO app_rw;
