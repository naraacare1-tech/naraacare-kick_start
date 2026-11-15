-- Care Circles (doc 04 section 2.9, doc 06 section 7, OQ-35, OQ-36). Username required.
--   * Seats: active members + open invites, max 50; checked with the circle row locked, so
--     concurrent invites/accepts cannot exceed it (CIRCLE_FULL).
--   * Every member shares 1..3 avatars; Sleep only with STAR (fn_validate_shares).
--   * Adding someone always creates an invite they must accept (Accept with shares / Decline /
--     Maybe later). Unknown, blocked or already-seated users are skipped silently.
--   * Leaving: if the last admin leaves, the earliest-joined active member becomes admin; an empty
--     circle is soft-deleted. Removed/left members lose access at once (membership checks are live).
--   * Notifications go through social.pr_notify (codes only) to members whose circle preferences
--     allow the category; pushes are sent by the worker from those rows (no message bodies).
-- Errors: 42501 not a member / not found (404), P0001 USERNAME_REQUIRED / ADMIN_REQUIRED /
--         CIRCLE_FULL / LAST_ADMIN / UPGRADE_REQUIRED, 22023 SHARES_INVALID / TOO_MANY_INVITEES /
--         INVALID_TARGET.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal: invite users (filtering out the inviter, unknown or blocked users and anyone already
-- holding a seat); returns the ids invited. The caller holds the circle row lock.
CREATE OR REPLACE FUNCTION social.fn_add_invites(p_circle_id uuid, p_inviter uuid, p_user_ids uuid[])
RETURNS uuid[]
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_targets uuid[];
BEGIN
    IF cardinality(coalesce(p_user_ids, '{}')) > 49 THEN
        RAISE EXCEPTION 'invite at most 49 people at once' USING ERRCODE = '22023', DETAIL = 'TOO_MANY_INVITEES';
    END IF;
    SELECT coalesce(array_agg(p.user_id), '{}') INTO v_targets
    FROM social.fn_public_profiles(ARRAY(SELECT DISTINCT u FROM unnest(p_user_ids) AS u)) AS p
    WHERE p.user_id <> p_inviter
      AND p.username IS NOT NULL
      AND NOT social.fn_is_blocked(p_inviter, p.user_id)
      AND NOT EXISTS (
          SELECT 1 FROM social.circle_member AS m
          WHERE m.circle_id = p_circle_id AND m.user_id = p.user_id
            AND m.status IN ('active', 'invited', 'maybe_later')
      );
    IF cardinality(v_targets) = 0 THEN
        RETURN v_targets;
    END IF;
    IF social.fn_seats_taken(p_circle_id) + cardinality(v_targets) > 50 THEN
        RAISE EXCEPTION 'this circle is full (50 members and invites)' USING ERRCODE = 'P0001', DETAIL = 'CIRCLE_FULL';
    END IF;
    INSERT INTO social.circle_member (circle_id, user_id, role, status, invited_by, invited_at)
    SELECT p_circle_id, t, 'member', 'invited', p_inviter, now() FROM unnest(v_targets) AS t
    ON CONFLICT (circle_id, user_id) DO UPDATE
    SET role = 'member', status = 'invited', invited_by = excluded.invited_by, invited_at = now(),
        joined_at = NULL, left_at = NULL, last_read_at = NULL;
    CALL social.pr_notify(
        v_targets, p_circle_id, 'circles', 'circle_invite', '{}', social.fn_circle_link(p_circle_id, '/invite')
    );
    RETURN v_targets;
END
$$;
COMMENT ON FUNCTION social.fn_add_invites(uuid, uuid, uuid[]) IS 'Internal: create invites (skips invalid targets; CIRCLE_FULL)';
REVOKE ALL ON FUNCTION social.fn_add_invites(uuid, uuid, uuid[]) FROM public;

CREATE OR REPLACE PROCEDURE social.pr_create_circle(
    p_user_id uuid,
    p_name common.safe_text,
    p_invitee_ids uuid[],
    p_shared_avatars text[],
    INOUT o_circle_id uuid DEFAULT NULL,
    INOUT o_invited integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_avatars text[];
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    v_avatars := social.fn_validate_shares(p_user_id, p_shared_avatars);
    INSERT INTO social.care_circle (name, created_by_user, member_count)
    VALUES (btrim(p_name), p_user_id, 1)
    RETURNING id INTO o_circle_id;
    INSERT INTO social.circle_member (circle_id, user_id, role, status, joined_at, last_read_at)
    VALUES (o_circle_id, p_user_id, 'admin', 'active', now(), now());
    CALL social.pr_apply_shares(o_circle_id, p_user_id, v_avatars);
    PERFORM 1 FROM social.care_circle WHERE id = o_circle_id FOR UPDATE;
    o_invited := cardinality(social.fn_add_invites(o_circle_id, p_user_id, p_invitee_ids));
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_invite_members(
    p_user_id uuid,
    p_circle_id uuid,
    p_user_ids uuid[],
    INOUT o_invited integer DEFAULT NULL
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
    o_invited := cardinality(social.fn_add_invites(p_circle_id, p_user_id, p_user_ids));
END
$$;

-- p_action: accept (with shares) | decline | later. o_status: the new membership status.
CREATE OR REPLACE PROCEDURE social.pr_respond_invite(
    p_user_id uuid,
    p_circle_id uuid,
    p_action text,
    p_shared_avatars text[] DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_avatars text[];
    v_status common.code;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    IF p_action NOT IN ('accept', 'decline', 'later') THEN
        RAISE EXCEPTION 'unknown action' USING ERRCODE = '22023', DETAIL = 'INVALID_ACTION';
    END IF;
    PERFORM 1 FROM social.care_circle AS c WHERE c.id = p_circle_id AND c.deleted_at IS NULL FOR UPDATE;
    SELECT m.status INTO v_status FROM social.circle_member AS m
    WHERE m.circle_id = p_circle_id AND m.user_id = p_user_id AND m.status IN ('invited', 'maybe_later')
    FOR UPDATE;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM social.care_circle AS c WHERE c.id = p_circle_id AND c.deleted_at IS NULL) THEN
        RAISE EXCEPTION 'invite not found' USING ERRCODE = '42501';
    END IF;

    IF p_action = 'decline' THEN
        UPDATE social.circle_member SET status = 'declined' WHERE circle_id = p_circle_id AND user_id = p_user_id;
        o_status := 'declined';
        RETURN;
    ELSIF p_action = 'later' THEN
        UPDATE social.circle_member SET status = 'maybe_later' WHERE circle_id = p_circle_id AND user_id = p_user_id;
        o_status := 'maybe_later';
        RETURN;
    END IF;

    v_avatars := social.fn_validate_shares(p_user_id, p_shared_avatars);
    -- The invite already holds a seat, so accepting never exceeds the cap.
    UPDATE social.circle_member
    SET status = 'active', joined_at = now(), left_at = NULL, last_read_at = now()
    WHERE circle_id = p_circle_id AND user_id = p_user_id;
    UPDATE social.care_circle SET member_count = member_count + 1 WHERE id = p_circle_id;
    CALL social.pr_apply_shares(p_circle_id, p_user_id, v_avatars);
    INSERT INTO social.activity_event (actor_id, event_type, circle_id) VALUES (p_user_id, 'joined', p_circle_id);
    CALL social.pr_notify(
        social.fn_recipients(p_circle_id, 'member_join_leave', p_user_id), p_circle_id, 'circles',
        'circle_member_joined', jsonb_build_object('user_id', p_user_id::text), social.fn_circle_link(p_circle_id)
    );
    o_status := 'active';
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_update_shares(p_user_id uuid, p_circle_id uuid, p_shared_avatars text[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    CALL social.pr_apply_shares(p_circle_id, p_user_id, social.fn_validate_shares(p_user_id, p_shared_avatars));
END
$$;

-- Internal: the member leaves (status 'left' or 'removed'); admin succession; empty -> soft delete.
-- Recipients are computed by the caller before the departure (afterwards they are not visible).
CREATE OR REPLACE PROCEDURE social.pr_depart(p_circle_id uuid, p_member_id uuid, p_status text)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_was_active boolean;
    v_was_admin boolean;
    v_successor uuid;
    v_count smallint;
BEGIN
    SELECT m.status = 'active', m.role = 'admin' INTO v_was_active, v_was_admin
    FROM social.circle_member AS m WHERE m.circle_id = p_circle_id AND m.user_id = p_member_id FOR UPDATE;

    IF v_was_active AND v_was_admin AND NOT EXISTS (
        SELECT 1 FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id AND m.status = 'active' AND m.role = 'admin' AND m.user_id <> p_member_id
    ) THEN
        SELECT m.user_id INTO v_successor FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id AND m.status = 'active' AND m.user_id <> p_member_id
        ORDER BY m.joined_at, m.user_id
        LIMIT 1;
        IF v_successor IS NOT NULL THEN
            UPDATE social.circle_member SET role = 'admin' WHERE circle_id = p_circle_id AND user_id = v_successor;
            CALL social.pr_notify(
                ARRAY[v_successor], p_circle_id, 'circles', 'circle_admin_granted', '{}', social.fn_circle_link(p_circle_id)
            );
        END IF;
    END IF;

    -- Counts and clean-up first: once the caller's own row says 'left', RLS no longer shows them
    -- the circle.
    IF v_was_active THEN
        UPDATE social.care_circle SET member_count = greatest(member_count - 1, 0) WHERE id = p_circle_id
        RETURNING member_count INTO v_count;
        IF v_count = 0 THEN
            UPDATE social.care_circle SET deleted_at = now() WHERE id = p_circle_id;
            UPDATE social.circle_member SET status = 'declined'
            WHERE circle_id = p_circle_id AND status IN ('invited', 'maybe_later');
            UPDATE social.circle_invite_link SET revoked_at = now() WHERE circle_id = p_circle_id AND revoked_at IS NULL;
        END IF;
    END IF;
    DELETE FROM social.circle_share WHERE circle_id = p_circle_id AND user_id = p_member_id;
    UPDATE social.circle_member
    SET status = p_status, role = 'member', left_at = now()
    WHERE circle_id = p_circle_id AND user_id = p_member_id;
END
$$;
COMMENT ON PROCEDURE social.pr_depart(uuid, uuid, text) IS 'Internal: leave/remove with admin succession and empty-circle soft delete';
REVOKE ALL ON PROCEDURE social.pr_depart(uuid, uuid, text) FROM public;

CREATE OR REPLACE PROCEDURE social.pr_leave_circle(p_user_id uuid, p_circle_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_recipients uuid[];
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    PERFORM 1 FROM social.care_circle WHERE id = p_circle_id FOR UPDATE;
    v_recipients := social.fn_recipients(p_circle_id, 'member_join_leave', p_user_id);
    CALL social.pr_depart(p_circle_id, p_user_id, 'left');
    INSERT INTO social.activity_event (actor_id, event_type, circle_id) VALUES (p_user_id, 'left', p_circle_id);
    CALL social.pr_notify(
        v_recipients, p_circle_id, 'circles', 'circle_member_left',
        jsonb_build_object('user_id', p_user_id::text), social.fn_circle_link(p_circle_id)
    );
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_remove_member(p_user_id uuid, p_circle_id uuid, p_member_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_admin(p_circle_id, p_user_id);
    IF p_member_id = p_user_id THEN
        RAISE EXCEPTION 'use leave to remove yourself' USING ERRCODE = '22023', DETAIL = 'INVALID_TARGET';
    END IF;
    PERFORM 1 FROM social.care_circle WHERE id = p_circle_id FOR UPDATE;
    IF NOT EXISTS (
        SELECT 1 FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id AND m.user_id = p_member_id AND m.status IN ('active', 'invited', 'maybe_later')
    ) THEN
        RAISE EXCEPTION 'member not found' USING ERRCODE = '42501';
    END IF;
    CALL social.pr_depart(p_circle_id, p_member_id, 'removed');
    CALL social.pr_notify(ARRAY[p_member_id], p_circle_id, 'circles', 'circle_removed', '{}', 'naraacare://circles');
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_set_member_role(
    p_user_id uuid, p_circle_id uuid, p_member_id uuid, p_role text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_admin(p_circle_id, p_user_id);
    IF p_role NOT IN ('admin', 'member') THEN
        RAISE EXCEPTION 'unknown role' USING ERRCODE = '22023', DETAIL = 'INVALID_ROLE';
    END IF;
    PERFORM 1 FROM social.care_circle WHERE id = p_circle_id FOR UPDATE;
    IF p_role = 'member' AND NOT EXISTS (
        SELECT 1 FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id AND m.status = 'active' AND m.role = 'admin' AND m.user_id <> p_member_id
    ) THEN
        RAISE EXCEPTION 'a circle needs at least one admin' USING ERRCODE = 'P0001', DETAIL = 'LAST_ADMIN';
    END IF;
    UPDATE social.circle_member SET role = p_role
    WHERE circle_id = p_circle_id AND user_id = p_member_id AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'member not found' USING ERRCODE = '42501';
    END IF;
    IF p_member_id <> p_user_id THEN
        CALL social.pr_notify(
            ARRAY[p_member_id], p_circle_id, 'circles',
            CASE p_role WHEN 'admin' THEN 'circle_admin_granted' ELSE 'circle_admin_revoked' END,
            '{}', social.fn_circle_link(p_circle_id)
        );
    END IF;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_update_circle(
    p_user_id uuid, p_circle_id uuid, p_name common.safe_text DEFAULT NULL, p_wallpaper_code common.code DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_admin(p_circle_id, p_user_id);
    UPDATE social.care_circle
    SET name = coalesce(nullif(btrim(p_name), ''), name),
        wallpaper_code = coalesce(p_wallpaper_code, wallpaper_code)
    WHERE id = p_circle_id;
    CALL social.pr_notify(
        social.fn_recipients(p_circle_id, 'circle_updates', p_user_id), p_circle_id, 'circles',
        'circle_updated', '{}', social.fn_circle_link(p_circle_id)
    );
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_delete_circle(p_user_id uuid, p_circle_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_recipients uuid[];
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_admin(p_circle_id, p_user_id);
    v_recipients := social.fn_recipients(p_circle_id, 'circle_updates', p_user_id);
    UPDATE social.care_circle SET deleted_at = now() WHERE id = p_circle_id;
    UPDATE social.circle_member SET status = 'declined'
    WHERE circle_id = p_circle_id AND status IN ('invited', 'maybe_later');
    UPDATE social.circle_invite_link SET revoked_at = now() WHERE circle_id = p_circle_id AND revoked_at IS NULL;
    CALL social.pr_notify(v_recipients, p_circle_id, 'circles', 'circle_deleted', '{}', 'naraacare://circles');
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_set_circle_prefs(
    p_user_id uuid,
    p_circle_id uuid,
    p_member_join_leave boolean,
    p_circle_updates boolean,
    p_goal_completions boolean,
    p_avatar_updates boolean,
    p_mentions boolean,
    p_new_messages boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    INSERT INTO notify.circle_notification_preference AS p (
        circle_id, user_id, member_join_leave, circle_updates, goal_completions, avatar_updates, mentions, new_messages
    ) VALUES (
        p_circle_id, p_user_id, p_member_join_leave, p_circle_updates, p_goal_completions, p_avatar_updates,
        p_mentions, p_new_messages
    )
    ON CONFLICT (circle_id, user_id) DO UPDATE
    SET member_join_leave = excluded.member_join_leave,
        circle_updates = excluded.circle_updates,
        goal_completions = excluded.goal_completions,
        avatar_updates = excluded.avatar_updates,
        mentions = excluded.mentions,
        new_messages = excluded.new_messages;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_mark_read(p_user_id uuid, p_circle_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    UPDATE social.circle_member SET last_read_at = now() WHERE circle_id = p_circle_id AND user_id = p_user_id;
END
$$;

COMMENT ON PROCEDURE social.pr_create_circle(uuid, common.safe_text, uuid[], text[], uuid, integer) IS
'Create a circle (caller = admin with 1..3 shares) and invite people';
COMMENT ON PROCEDURE social.pr_invite_members(uuid, uuid, uuid[], integer) IS 'Admin: invite people (CIRCLE_FULL at 50 seats)';
COMMENT ON PROCEDURE social.pr_respond_invite(uuid, uuid, text, text[], text) IS 'Accept (with shares), decline or postpone an invite';
COMMENT ON PROCEDURE social.pr_update_shares(uuid, uuid, text[]) IS 'Change the avatars the caller shares (1..3)';
COMMENT ON PROCEDURE social.pr_leave_circle(uuid, uuid) IS 'Leave a circle (admin succession; empty circle deleted)';
COMMENT ON PROCEDURE social.pr_remove_member(uuid, uuid, uuid) IS 'Admin: remove a member or cancel an invite';
COMMENT ON PROCEDURE social.pr_set_member_role(uuid, uuid, uuid, text) IS 'Admin: make or unmake an admin (LAST_ADMIN)';
COMMENT ON PROCEDURE social.pr_update_circle(uuid, uuid, common.safe_text, common.code) IS 'Admin: rename / change wallpaper';
COMMENT ON PROCEDURE social.pr_delete_circle(uuid, uuid) IS 'Admin: delete a circle (soft delete)';
COMMENT ON PROCEDURE social.pr_set_circle_prefs(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) IS
'Per-circle notification switches';
COMMENT ON PROCEDURE social.pr_mark_read(uuid, uuid) IS 'Mark the circle chat read';

REVOKE ALL ON PROCEDURE social.pr_create_circle(uuid, common.safe_text, uuid[], text[], uuid, integer) FROM public;
REVOKE ALL ON PROCEDURE social.pr_invite_members(uuid, uuid, uuid[], integer) FROM public;
REVOKE ALL ON PROCEDURE social.pr_respond_invite(uuid, uuid, text, text[], text) FROM public;
REVOKE ALL ON PROCEDURE social.pr_update_shares(uuid, uuid, text[]) FROM public;
REVOKE ALL ON PROCEDURE social.pr_leave_circle(uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE social.pr_remove_member(uuid, uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE social.pr_set_member_role(uuid, uuid, uuid, text) FROM public;
REVOKE ALL ON PROCEDURE social.pr_update_circle(uuid, uuid, common.safe_text, common.code) FROM public;
REVOKE ALL ON PROCEDURE social.pr_delete_circle(uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE social.pr_set_circle_prefs(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) FROM public;
REVOKE ALL ON PROCEDURE social.pr_mark_read(uuid, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE social.pr_create_circle(uuid, common.safe_text, uuid[], text[], uuid, integer) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_invite_members(uuid, uuid, uuid[], integer) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_respond_invite(uuid, uuid, text, text[], text) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_update_shares(uuid, uuid, text[]) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_leave_circle(uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_remove_member(uuid, uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_set_member_role(uuid, uuid, uuid, text) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_update_circle(uuid, uuid, common.safe_text, common.code) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_delete_circle(uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_set_circle_prefs(uuid, uuid, boolean, boolean, boolean, boolean, boolean, boolean) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_mark_read(uuid, uuid) TO app_rw;
