-- PUT /me/username (doc 04 section 2.2, OQ-24). The common.username parameter type rejects invalid
-- formats (23514) before the body runs; the domain only allows lower case, so uniqueness is
-- case-insensitive by construction.
-- The first username is free; changing an existing one is allowed once per 90 days.
-- Uniqueness is decided by uq_user_profile__username, not by a prior SELECT, so two users racing for
-- the same name cannot both win (RLS hides other rows, but the unique index still sees them).
-- Errors: P0001 USERNAME_TAKEN / USERNAME_CHANGE_TOO_SOON / ONBOARDING_INCOMPLETE.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_set_username(
    p_user_id uuid,
    p_username common.username
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_profile app.user_profile%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_username IS NULL THEN
        RAISE EXCEPTION 'username is required' USING ERRCODE = '22023', DETAIL = 'USERNAME_REQUIRED';
    END IF;
    SELECT * INTO v_profile FROM app.user_profile WHERE user_id = p_user_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    IF v_profile.username = p_username THEN
        RETURN;
    END IF;
    IF v_profile.username IS NOT NULL AND v_profile.username_changed_at > now() - interval '90 days' THEN
        RAISE EXCEPTION 'username can be changed once every 90 days'
            USING ERRCODE = 'P0001', DETAIL = 'USERNAME_CHANGE_TOO_SOON';
    END IF;

    BEGIN
        UPDATE app.user_profile
        SET username = p_username, username_changed_at = now()
        WHERE user_id = p_user_id;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'username is taken' USING ERRCODE = 'P0001', DETAIL = 'USERNAME_TAKEN';
    END;
END
$$;

COMMENT ON PROCEDURE app.pr_set_username (uuid, common.username) IS
'Set or change the username (unique, change once per 90 days)';
REVOKE ALL ON PROCEDURE app.pr_set_username(uuid, common.username) FROM public;
GRANT EXECUTE ON PROCEDURE app.pr_set_username(uuid, common.username) TO app_rw;
