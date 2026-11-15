-- POST /auth/oauth/link: attach a verified Google/Apple identity to the actor's account after the API
-- has checked the account password. One identity per provider subject (uq_identity_link__provider_subject).
-- Errors: P0001 IDENTITY_ALREADY_LINKED when the subject belongs to another account.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE auth.pr_link_identity(
    p_user_id uuid,
    p_provider common.code,
    p_subject common.opaque_ref,
    p_email common.email DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_owner uuid;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);

    SELECT i.user_id INTO v_owner
    FROM auth.identity_link AS i
    WHERE i.provider = p_provider AND i.subject = p_subject;
    IF v_owner = p_user_id THEN
        RETURN;
    ELSIF v_owner IS NOT NULL THEN
        RAISE EXCEPTION 'identity is linked to another account'
            USING ERRCODE = 'P0001', DETAIL = 'IDENTITY_ALREADY_LINKED';
    END IF;

    INSERT INTO auth.identity_link (user_id, provider, subject, email)
    VALUES (p_user_id, p_provider, p_subject, p_email);
EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'identity is linked to another account'
        USING ERRCODE = 'P0001', DETAIL = 'IDENTITY_ALREADY_LINKED';
END
$$;

COMMENT ON PROCEDURE auth.pr_link_identity (uuid, common.code, common.opaque_ref, common.email) IS
'Link a verified Google/Apple identity to the actor; IDENTITY_ALREADY_LINKED if taken';
REVOKE ALL ON PROCEDURE auth.pr_link_identity(uuid, common.code, common.opaque_ref, common.email) FROM public;
GRANT EXECUTE ON PROCEDURE auth.pr_link_identity(uuid, common.code, common.opaque_ref, common.email) TO app_rw;
