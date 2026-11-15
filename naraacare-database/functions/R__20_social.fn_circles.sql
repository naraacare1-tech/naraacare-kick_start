-- Care Circle reads (doc 04 section 2.9, doc 06 section 7). Every function checks active membership
-- (42501 -> 404 for anyone else) before returning anything.
--   * Visibility of a member's avatar: shared with this circle, and for Sleep both owner and viewer
--     are STAR now (otherwise 'requires_star'; a downgraded owner's share is kept but hidden).
--   * Feed (fan-out-on-read): avatar events of active members who share that avatar here, since
--     shared_since, plus join/leave events and avatar cards shared into this circle (V029); Sleep events follow the Sleep rule; users the viewer
--     blocked (or who blocked the viewer) are left out. Changing shares changes the feed at once.
--   * Messages: deleted ones keep their place with body NULL; senders blocked by the viewer hidden.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal: feed rows of a circle visible to a member (no membership check; callers do that).
CREATE OR REPLACE FUNCTION social.fn_feed_rows(
    p_user_id uuid, p_circle_id uuid, p_since timestamptz, p_before timestamptz, p_limit integer
)
RETURNS TABLE (
    event_id uuid,
    occurred_at timestamptz,
    actor_id uuid,
    event_type common.code,
    avatar_type common.code,
    summary jsonb
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    WITH viewer_star AS (SELECT social.fn_is_star(p_user_id) AS star),
    shares AS (
        SELECT s.user_id, s.avatar_type, s.shared_since
        FROM social.circle_share AS s
        INNER JOIN social.circle_member AS m
            ON m.circle_id = s.circle_id AND m.user_id = s.user_id AND m.status = 'active'
        WHERE s.circle_id = p_circle_id
          AND NOT social.fn_is_blocked(p_user_id, s.user_id)
          AND (s.avatar_type <> 'sleep' OR ((SELECT star FROM viewer_star) AND social.fn_is_star(s.user_id)))
    )
    SELECT e.id, e.occurred_at, e.actor_id, e.event_type, e.avatar_type, e.summary
    FROM shares AS sh
    INNER JOIN social.activity_event AS e
        ON e.actor_id = sh.user_id AND e.avatar_type = sh.avatar_type
    -- Only the actor's own avatar events; a card shared into one circle (V029) never shows in another.
    WHERE e.circle_id IS NULL
      AND e.occurred_at >= greatest(sh.shared_since, coalesce(p_since, '-infinity'))
      AND e.occurred_at < coalesce(p_before, 'infinity')
    UNION ALL
    SELECT e.id, e.occurred_at, e.actor_id, e.event_type, e.avatar_type, e.summary
    FROM social.activity_event AS e
    WHERE e.circle_id = p_circle_id
      AND e.occurred_at >= coalesce(p_since, '-infinity')
      AND e.occurred_at < coalesce(p_before, 'infinity')
      AND NOT social.fn_is_blocked(p_user_id, e.actor_id)
      -- A Sleep card shared on purpose (V029) follows the Sleep rule too.
      AND (e.avatar_type IS DISTINCT FROM 'sleep'
           OR ((SELECT star FROM viewer_star) AND social.fn_is_star(e.actor_id)))
    ORDER BY 2 DESC, 1 DESC
    LIMIT p_limit
$$;
COMMENT ON FUNCTION social.fn_feed_rows(uuid, uuid, timestamptz, timestamptz, integer) IS
'Internal: Recent Updates rows visible to a member (fan-out-on-read)';
REVOKE ALL ON FUNCTION social.fn_feed_rows(uuid, uuid, timestamptz, timestamptz, integer) FROM public;

CREATE OR REPLACE FUNCTION social.fn_circles_for_user(p_user_id uuid)
RETURNS TABLE (
    circle_id uuid,
    name common.safe_text,
    wallpaper_code common.code,
    member_count smallint,
    my_role common.code,
    updates_today integer,
    unread integer,
    last_message_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_day_start timestamptz;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    SELECT (common.fn_local_date(p.timezone)::timestamp AT TIME ZONE p.timezone) INTO v_day_start
    FROM app.user_profile AS p WHERE p.user_id = p_user_id;
    RETURN QUERY
    SELECT
        c.id, c.name, c.wallpaper_code, c.member_count, m.role,
        (SELECT count(*)::integer FROM social.fn_feed_rows(p_user_id, c.id, v_day_start, NULL, 1000)),
        (
            SELECT count(*)::integer FROM social.chat_message AS cm
            WHERE cm.circle_id = c.id AND cm.deleted_at IS NULL AND cm.sender_id <> p_user_id
              AND cm.created_at > coalesce(m.last_read_at, m.joined_at)
              AND NOT EXISTS (
                  SELECT 1 FROM social.user_block AS b WHERE b.blocker_id = p_user_id AND b.blocked_id = cm.sender_id
              )
        ),
        (SELECT max(cm.created_at) FROM social.chat_message AS cm WHERE cm.circle_id = c.id)
    FROM social.circle_member AS m
    INNER JOIN social.care_circle AS c ON c.id = m.circle_id AND c.deleted_at IS NULL
    WHERE m.user_id = p_user_id AND m.status = 'active'
    ORDER BY 8 DESC NULLS LAST, c.name;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_circle_detail(p_user_id uuid, p_circle_id uuid)
RETURNS TABLE (
    circle_id uuid,
    name common.safe_text,
    wallpaper_code common.code,
    member_count smallint,
    my_role common.code,
    my_shares text[],
    preferences jsonb,
    members_preview jsonb,
    last_message jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    RETURN QUERY
    SELECT
        c.id, c.name, c.wallpaper_code, c.member_count, m.role,
        coalesce(ARRAY(
            SELECT s.avatar_type::text FROM social.circle_share AS s
            WHERE s.circle_id = c.id AND s.user_id = p_user_id ORDER BY s.avatar_type
        ), '{}'),
        jsonb_build_object(
            'member_join_leave', coalesce(pr.member_join_leave, TRUE),
            'circle_updates', coalesce(pr.circle_updates, TRUE),
            'goal_completions', coalesce(pr.goal_completions, TRUE),
            'avatar_updates', coalesce(pr.avatar_updates, FALSE),
            'mentions', coalesce(pr.mentions, TRUE),
            'new_messages', coalesce(pr.new_messages, FALSE)
        ),
        (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'user_id', x.user_id, 'username', x.username, 'display_initial', x.display_initial,
                'avatar_code', x.avatar_code, 'role', x.role
            ) ORDER BY x.role, x.joined_at), '[]')
            FROM (
                SELECT p.user_id, p.username, p.display_initial, p.avatar_code, om.role, om.joined_at
                FROM social.circle_member AS om
                INNER JOIN social.fn_public_profiles(ARRAY(
                    SELECT om2.user_id FROM social.circle_member AS om2
                    WHERE om2.circle_id = p_circle_id AND om2.status = 'active'
                )) AS p ON p.user_id = om.user_id
                WHERE om.circle_id = p_circle_id AND om.status = 'active'
                ORDER BY (om.role = 'admin') DESC, om.joined_at
                LIMIT 6
            ) AS x
        ),
        (
            SELECT jsonb_build_object(
                'message_id', lm.id, 'sender_id', lm.sender_id, 'created_at', lm.created_at,
                'body', CASE WHEN lm.deleted_at IS NULL THEN lm.body END
            )
            FROM social.chat_message AS lm
            WHERE lm.circle_id = c.id
              AND NOT EXISTS (
                  SELECT 1 FROM social.user_block AS b WHERE b.blocker_id = p_user_id AND b.blocked_id = lm.sender_id
              )
            ORDER BY lm.created_at DESC
            LIMIT 1
        )
    FROM social.care_circle AS c
    INNER JOIN social.circle_member AS m ON m.circle_id = c.id AND m.user_id = p_user_id
    LEFT JOIN notify.circle_notification_preference AS pr ON pr.circle_id = c.id AND pr.user_id = p_user_id
    WHERE c.id = p_circle_id;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_circle_members(
    p_user_id uuid, p_circle_id uuid, p_query text DEFAULT NULL, p_after common.username DEFAULT NULL,
    p_limit integer DEFAULT 50
)
RETURNS TABLE (
    user_id uuid,
    username common.username,
    display_name text,
    display_initial text,
    avatar_code common.code,
    role common.code,
    status common.code,
    joined_at timestamptz,
    shares text[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    RETURN QUERY
    SELECT
        p.user_id, p.username, p.display_name, p.display_initial, p.avatar_code, m.role, m.status, m.joined_at,
        coalesce(ARRAY(
            SELECT s.avatar_type::text FROM social.circle_share AS s
            WHERE s.circle_id = m.circle_id AND s.user_id = m.user_id ORDER BY s.avatar_type
        ), '{}')
    FROM social.circle_member AS m
    INNER JOIN social.fn_public_profiles(ARRAY(
        SELECT m2.user_id FROM social.circle_member AS m2
        WHERE m2.circle_id = p_circle_id AND m2.status IN ('active', 'invited', 'maybe_later')
    )) AS p ON p.user_id = m.user_id
    WHERE m.circle_id = p_circle_id
      AND m.status IN ('active', 'invited', 'maybe_later')
      AND (p_query IS NULL OR p.username::text LIKE
           replace(replace(replace(lower(btrim(ltrim(p_query, '@'))), '\', '\\'), '%', '\%'), '_', '\_') || '%')
      AND (p_after IS NULL OR p.username > p_after)
    ORDER BY (m.status = 'active') DESC, (m.role = 'admin') DESC, p.username
    LIMIT least(greatest(coalesce(p_limit, 50), 1), 50);
END
$$;

-- One row per avatar type: shared (with today's values) | not_shared | requires_star.
CREATE OR REPLACE FUNCTION social.fn_member_avatars(p_user_id uuid, p_circle_id uuid, p_member_id uuid)
RETURNS TABLE (
    avatar_type text,
    visibility text,
    state jsonb,
    shared_since timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_viewer_star boolean;
    v_owner_star boolean;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    IF NOT EXISTS (
        SELECT 1 FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id AND m.user_id = p_member_id AND m.status = 'active'
    ) OR social.fn_is_blocked(p_user_id, p_member_id) THEN
        RAISE EXCEPTION 'member not found' USING ERRCODE = '42501';
    END IF;
    v_viewer_star := social.fn_is_star(p_user_id);
    v_owner_star := social.fn_is_star(p_member_id);
    RETURN QUERY
    SELECT
        t.a,
        CASE
            WHEN s.avatar_type IS NULL THEN 'not_shared'
            WHEN t.a = 'sleep' AND NOT (v_viewer_star AND v_owner_star) THEN 'requires_star'
            ELSE 'shared'
        END,
        CASE
            WHEN s.avatar_type IS NOT NULL AND (t.a <> 'sleep' OR (v_viewer_star AND v_owner_star))
                THEN social.fn_avatar_state(p_member_id, t.a)
        END,
        s.shared_since
    FROM unnest(ARRAY['hydration', 'nutrition', 'sleep']) AS t (a)
    LEFT JOIN social.circle_share AS s
        ON s.circle_id = p_circle_id AND s.user_id = p_member_id AND s.avatar_type = t.a;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_circle_feed(
    p_user_id uuid, p_circle_id uuid, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 30
)
RETURNS TABLE (
    event_id uuid,
    occurred_at timestamptz,
    actor_id uuid,
    username common.username,
    display_initial text,
    avatar_code common.code,
    event_type common.code,
    avatar_type common.code,
    summary jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    RETURN QUERY
    WITH rows AS (
        SELECT * FROM social.fn_feed_rows(
            p_user_id, p_circle_id, NULL, p_before, least(greatest(coalesce(p_limit, 30), 1), 50)
        )
    )
    SELECT r.event_id, r.occurred_at, r.actor_id, p.username, p.display_initial, p.avatar_code,
           r.event_type, r.avatar_type, r.summary
    FROM rows AS r
    LEFT JOIN social.fn_public_profiles(ARRAY(SELECT DISTINCT r2.actor_id FROM rows AS r2)) AS p
        ON p.user_id = r.actor_id
    ORDER BY r.occurred_at DESC, r.event_id DESC;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_messages(
    p_user_id uuid, p_circle_id uuid, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 50
)
RETURNS TABLE (
    message_id uuid,
    created_at timestamptz,
    sender_id uuid,
    username common.username,
    display_initial text,
    avatar_code common.code,
    body text,
    deleted boolean,
    mention_user_ids uuid[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    RETURN QUERY
    WITH msgs AS (
        SELECT m.id, m.created_at, m.sender_id, m.body, m.deleted_at
        FROM social.chat_message AS m
        WHERE m.circle_id = p_circle_id
          AND m.created_at < coalesce(p_before, 'infinity')
          AND NOT EXISTS (
              SELECT 1 FROM social.user_block AS b WHERE b.blocker_id = p_user_id AND b.blocked_id = m.sender_id
          )
        ORDER BY m.created_at DESC
        LIMIT least(greatest(coalesce(p_limit, 50), 1), 50)
    )
    SELECT
        m.id, m.created_at, m.sender_id, p.username, p.display_initial, p.avatar_code,
        CASE WHEN m.deleted_at IS NULL THEN m.body::text END,
        m.deleted_at IS NOT NULL,
        coalesce(ARRAY(
            SELECT cm.mentioned_user_id FROM social.chat_mention AS cm
            WHERE cm.message_id = m.id AND cm.message_created_at = m.created_at
        ), '{}')
    FROM msgs AS m
    LEFT JOIN social.fn_public_profiles(ARRAY(SELECT DISTINCT m2.sender_id FROM msgs AS m2)) AS p
        ON p.user_id = m.sender_id
    ORDER BY m.created_at DESC;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_pending_invites(p_user_id uuid)
RETURNS TABLE (
    circle_id uuid,
    name common.safe_text,
    wallpaper_code common.code,
    member_count smallint,
    status common.code,
    invited_at timestamptz,
    inviter_username common.username
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    RETURN QUERY
    SELECT c.id, c.name, c.wallpaper_code, c.member_count, m.status, m.invited_at, p.username
    FROM social.circle_member AS m
    INNER JOIN social.care_circle AS c ON c.id = m.circle_id AND c.deleted_at IS NULL
    LEFT JOIN social.fn_public_profiles(ARRAY(
        SELECT m2.invited_by FROM social.circle_member AS m2
        WHERE m2.user_id = p_user_id AND m2.status IN ('invited', 'maybe_later') AND m2.invited_by IS NOT NULL
    )) AS p ON p.user_id = m.invited_by
    WHERE m.user_id = p_user_id
      AND m.status IN ('invited', 'maybe_later')
      AND (m.invited_by IS NULL OR NOT social.fn_is_blocked(p_user_id, m.invited_by))
    ORDER BY (m.status = 'invited') DESC, m.invited_at DESC;
END
$$;

COMMENT ON FUNCTION social.fn_circles_for_user(uuid) IS 'Your Circles: active circles with updates today and unread count';
COMMENT ON FUNCTION social.fn_circle_detail(uuid, uuid) IS 'Circle home: circle, my role/shares/preferences, members preview, last message';
COMMENT ON FUNCTION social.fn_circle_members(uuid, uuid, text, common.username, integer) IS
'Members and invitees (admins first), username filter, keyset by username';
COMMENT ON FUNCTION social.fn_member_avatars(uuid, uuid, uuid) IS 'A member''s avatars as the caller may see them';
COMMENT ON FUNCTION social.fn_circle_feed(uuid, uuid, timestamptz, integer) IS 'Recent Updates (keyset by time)';
COMMENT ON FUNCTION social.fn_messages(uuid, uuid, timestamptz, integer) IS 'Chat page, newest first (keyset by time)';
COMMENT ON FUNCTION social.fn_pending_invites(uuid) IS 'Circle invites waiting for the caller';

REVOKE ALL ON FUNCTION social.fn_circles_for_user(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_circle_detail(uuid, uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_circle_members(uuid, uuid, text, common.username, integer) FROM public;
REVOKE ALL ON FUNCTION social.fn_member_avatars(uuid, uuid, uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_circle_feed(uuid, uuid, timestamptz, integer) FROM public;
REVOKE ALL ON FUNCTION social.fn_messages(uuid, uuid, timestamptz, integer) FROM public;
REVOKE ALL ON FUNCTION social.fn_pending_invites(uuid) FROM public;
GRANT EXECUTE ON FUNCTION social.fn_circles_for_user(uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_circle_detail(uuid, uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_circle_members(uuid, uuid, text, common.username, integer) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_member_avatars(uuid, uuid, uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_circle_feed(uuid, uuid, timestamptz, integer) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_messages(uuid, uuid, timestamptz, integer) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_pending_invites(uuid) TO app_rw;
