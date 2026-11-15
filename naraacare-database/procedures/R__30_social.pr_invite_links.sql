-- Circle invite links (doc 04 section 2.9, OQ-35). The API makes a 256-bit random token, returns it
-- once inside the link and passes only its SHA-256 here (the token is a bearer secret, hashed like
-- refresh tokens). Links last 7 days, allow max_uses joins (1..49), at most 10 per circle per day,
-- and admins can revoke them.
--   * pr_resolve_invite_link(token hash): turns the link into a normal invite for the caller (who
--     then accepts with shares). o_status invited | member (already in the circle).
-- Errors: 42501 unknown link / circle (404), P0001 INVITE_LINK_EXPIRED (410) / CIRCLE_FULL (409) /
--         INVITE_LINK_LIMIT (429) / ADMIN_REQUIRED / USERNAME_REQUIRED.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE social.pr_create_invite_link(
    p_user_id uuid,
    p_circle_id uuid,
    p_token_hash common.blind_index,
    p_max_uses smallint DEFAULT NULL,
    INOUT o_link_id uuid DEFAULT NULL,
    INOUT o_expires_at timestamptz DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    PERFORM social.fn_require_admin(p_circle_id, p_user_id);
    PERFORM 1 FROM social.care_circle WHERE id = p_circle_id FOR UPDATE;
    IF (
        SELECT count(*) FROM social.circle_invite_link AS l
        WHERE l.circle_id = p_circle_id AND l.created_at > now() - interval '1 day'
    ) >= 10 THEN
        RAISE EXCEPTION 'at most 10 invite links per circle per day' USING ERRCODE = 'P0001', DETAIL = 'INVITE_LINK_LIMIT';
    END IF;
    INSERT INTO social.circle_invite_link (circle_id, token_hash, created_by, expires_at, max_uses)
    VALUES (p_circle_id, p_token_hash, p_user_id, now() + interval '7 days', coalesce(p_max_uses, 49))
    RETURNING id, expires_at INTO o_link_id, o_expires_at;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_revoke_invite_link(p_user_id uuid, p_circle_id uuid, p_link_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_admin(p_circle_id, p_user_id);
    UPDATE social.circle_invite_link SET revoked_at = coalesce(revoked_at, now())
    WHERE id = p_link_id AND circle_id = p_circle_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'link not found' USING ERRCODE = '42501';
    END IF;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_resolve_invite_link(
    p_user_id uuid,
    p_token_hash common.blind_index,
    INOUT o_circle_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_link social.circle_invite_link%ROWTYPE;
    v_status common.code;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    SELECT * INTO v_link FROM social.circle_invite_link AS l WHERE l.token_hash = p_token_hash FOR UPDATE;
    IF NOT FOUND OR (v_link.created_by IS NOT NULL AND social.fn_is_blocked(p_user_id, v_link.created_by)) THEN
        RAISE EXCEPTION 'invite link not found' USING ERRCODE = '42501';
    END IF;
    o_circle_id := v_link.circle_id;

    SELECT m.status INTO v_status FROM social.circle_member AS m
    WHERE m.circle_id = v_link.circle_id AND m.user_id = p_user_id;
    IF v_status = 'active' THEN
        o_status := 'member';
        RETURN;
    END IF;
    IF v_link.revoked_at IS NOT NULL OR v_link.expires_at <= now() OR v_link.use_count >= v_link.max_uses THEN
        RAISE EXCEPTION 'this invite link has expired' USING ERRCODE = 'P0001', DETAIL = 'INVITE_LINK_EXPIRED';
    END IF;
    IF v_status IN ('invited', 'maybe_later') THEN
        o_status := 'invited';  -- already holds a seat; the link is not used up again
        RETURN;
    END IF;

    -- The caller becomes an invitee first: only then may RLS show them the circle.
    INSERT INTO social.circle_member (circle_id, user_id, role, status, invited_by, invited_at)
    VALUES (v_link.circle_id, p_user_id, 'member', 'invited', v_link.created_by, now())
    ON CONFLICT (circle_id, user_id) DO UPDATE
    SET role = 'member', status = 'invited', invited_by = excluded.invited_by, invited_at = now(),
        joined_at = NULL, left_at = NULL, last_read_at = NULL;
    PERFORM 1 FROM social.care_circle AS c WHERE c.id = v_link.circle_id FOR UPDATE;
    IF NOT EXISTS (SELECT 1 FROM social.care_circle AS c WHERE c.id = v_link.circle_id AND c.deleted_at IS NULL) THEN
        RAISE EXCEPTION 'invite link not found' USING ERRCODE = '42501';
    END IF;
    IF social.fn_seats_taken(v_link.circle_id) > 50 THEN
        RAISE EXCEPTION 'this circle is full (50 members and invites)' USING ERRCODE = 'P0001', DETAIL = 'CIRCLE_FULL';
    END IF;
    UPDATE social.circle_invite_link SET use_count = use_count + 1 WHERE id = v_link.id;
    o_status := 'invited';
END
$$;

COMMENT ON PROCEDURE social.pr_create_invite_link(uuid, uuid, common.blind_index, smallint, uuid, timestamptz) IS
'Admin: store a new invite link (token hash), 7 days, max uses, 10 per circle per day';
COMMENT ON PROCEDURE social.pr_revoke_invite_link(uuid, uuid, uuid) IS 'Admin: revoke an invite link';
COMMENT ON PROCEDURE social.pr_resolve_invite_link(uuid, common.blind_index, uuid, text) IS
'Turn an invite link into an invite for the caller: invited | member';

REVOKE ALL ON PROCEDURE social.pr_create_invite_link(uuid, uuid, common.blind_index, smallint, uuid, timestamptz) FROM public;
REVOKE ALL ON PROCEDURE social.pr_revoke_invite_link(uuid, uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE social.pr_resolve_invite_link(uuid, common.blind_index, uuid, text) FROM public;
GRANT EXECUTE ON PROCEDURE social.pr_create_invite_link(uuid, uuid, common.blind_index, smallint, uuid, timestamptz) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_revoke_invite_link(uuid, uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_resolve_invite_link(uuid, common.blind_index, uuid, text) TO app_rw;
