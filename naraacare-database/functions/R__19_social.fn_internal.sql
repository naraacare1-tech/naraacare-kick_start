-- Internal helpers for the social routines (Session 12). Not executable by the app roles; only the
-- api_definer routines call them. Errors: 42501 = not found for the caller (API 404), P0001 with a
-- DETAIL code for business rules, 22023 for invalid input.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Username gate for every social action (doc 06 section 7). Returns the caller's username.
CREATE OR REPLACE FUNCTION social.fn_require_username(p_user_id uuid)
RETURNS common.username
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_username common.username;
BEGIN
    SELECT p.username INTO v_username
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.deleted_at IS NULL;
    IF v_username IS NULL THEN
        RAISE EXCEPTION 'choose a username first' USING ERRCODE = 'P0001', DETAIL = 'USERNAME_REQUIRED';
    END IF;
    RETURN v_username;
END
$$;
COMMENT ON FUNCTION social.fn_require_username(uuid) IS 'Internal: USERNAME_REQUIRED unless the user has a username';

-- Either user blocked the other.
CREATE OR REPLACE FUNCTION social.fn_is_blocked(p_a uuid, p_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM social.user_block AS b
        WHERE (b.blocker_id = p_a AND b.blocked_id = p_b) OR (b.blocker_id = p_b AND b.blocked_id = p_a)
    )
$$;
COMMENT ON FUNCTION social.fn_is_blocked(uuid, uuid) IS 'Internal: a block exists in either direction';

-- Active membership: the caller's role, or 42501 (the API answers 404, so non-members cannot even
-- learn that the circle exists).
CREATE OR REPLACE FUNCTION social.fn_require_member(p_circle_id uuid, p_user_id uuid)
RETURNS common.code
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_role common.code;
BEGIN
    SELECT m.role INTO v_role
    FROM social.circle_member AS m
    INNER JOIN social.care_circle AS c ON c.id = m.circle_id AND c.deleted_at IS NULL
    WHERE m.circle_id = p_circle_id AND m.user_id = p_user_id AND m.status = 'active';
    IF v_role IS NULL THEN
        RAISE EXCEPTION 'circle not found' USING ERRCODE = '42501';
    END IF;
    RETURN v_role;
END
$$;
COMMENT ON FUNCTION social.fn_require_member(uuid, uuid) IS 'Internal: role of an active member, else 42501';

CREATE OR REPLACE FUNCTION social.fn_require_admin(p_circle_id uuid, p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF social.fn_require_member(p_circle_id, p_user_id) <> 'admin' THEN
        RAISE EXCEPTION 'only circle admins can do this' USING ERRCODE = 'P0001', DETAIL = 'ADMIN_REQUIRED';
    END IF;
END
$$;
COMMENT ON FUNCTION social.fn_require_admin(uuid, uuid) IS 'Internal: 42501 if not a member, ADMIN_REQUIRED if not admin';

-- Shares chosen when creating, accepting or editing: 1..3 distinct avatars; sleep only with STAR.
CREATE OR REPLACE FUNCTION social.fn_validate_shares(p_user_id uuid, p_avatars text[])
RETURNS text[]
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_avatars text[];
BEGIN
    SELECT array_agg(DISTINCT a ORDER BY a) INTO v_avatars FROM unnest(p_avatars) AS a;
    IF v_avatars IS NULL OR cardinality(v_avatars) = 0
       OR NOT v_avatars <@ ARRAY['hydration', 'nutrition', 'sleep'] THEN
        RAISE EXCEPTION 'share at least one avatar' USING ERRCODE = '22023', DETAIL = 'SHARES_INVALID';
    END IF;
    IF 'sleep' = ANY (v_avatars) AND NOT social.fn_is_star(p_user_id) THEN
        RAISE EXCEPTION 'sharing the Sleep avatar needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;
    RETURN v_avatars;
END
$$;
COMMENT ON FUNCTION social.fn_validate_shares(uuid, text[]) IS
'Internal: 1..3 known avatars (SHARES_INVALID); sleep needs STAR (UPGRADE_REQUIRED)';

-- Replace a member's shares. Kept rows keep shared_since; new rows start now (the feed shows a new
-- share from now on, and a removed share hides that avatar's past events at once).
CREATE OR REPLACE PROCEDURE social.pr_apply_shares(p_circle_id uuid, p_user_id uuid, p_avatars text[])
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    DELETE FROM social.circle_share AS s
    WHERE s.circle_id = p_circle_id AND s.user_id = p_user_id AND NOT s.avatar_type = ANY (p_avatars);
    INSERT INTO social.circle_share (circle_id, user_id, avatar_type)
    SELECT p_circle_id, p_user_id, a FROM unnest(p_avatars) AS a
    ON CONFLICT (circle_id, user_id, avatar_type) DO NOTHING;
END
$$;
COMMENT ON PROCEDURE social.pr_apply_shares(uuid, uuid, text[]) IS 'Internal: set a member''s shares (kept rows keep shared_since)';

-- Active members of a circle who want a notification category (no preference row = defaults).
CREATE OR REPLACE FUNCTION social.fn_recipients(p_circle_id uuid, p_category text, p_exclude uuid)
RETURNS uuid[]
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT coalesce(array_agg(m.user_id), '{}')
    FROM social.circle_member AS m
    LEFT JOIN notify.circle_notification_preference AS p
        ON p.circle_id = m.circle_id AND p.user_id = m.user_id
    WHERE m.circle_id = p_circle_id
      AND m.status = 'active'
      AND m.user_id IS DISTINCT FROM p_exclude
      AND CASE p_category
          WHEN 'member_join_leave' THEN coalesce(p.member_join_leave, TRUE)
          WHEN 'circle_updates' THEN coalesce(p.circle_updates, TRUE)
          WHEN 'goal_completions' THEN coalesce(p.goal_completions, TRUE)
          WHEN 'avatar_updates' THEN coalesce(p.avatar_updates, FALSE)
          WHEN 'mentions' THEN coalesce(p.mentions, TRUE)
          WHEN 'new_messages' THEN coalesce(p.new_messages, FALSE)
          ELSE FALSE
      END
$$;
COMMENT ON FUNCTION social.fn_recipients(uuid, text, uuid) IS
'Internal: active members (except one) whose circle preferences allow a category';

-- Circle deep link for notifications.
CREATE OR REPLACE FUNCTION social.fn_circle_link(p_circle_id uuid, p_suffix text DEFAULT '')
RETURNS common.deep_link
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT ('naraacare://circles/' || p_circle_id::text || p_suffix)::common.deep_link
$$;
COMMENT ON FUNCTION social.fn_circle_link(uuid, text) IS 'Internal: naraacare://circles/<id>[suffix]';

-- Feed event for the actor's avatar (Session 12 step 6): written only when the actor shares that
-- avatar with at least one active circle (nobody else could see it otherwise). goal_completed also
-- notifies members of those circles who keep goal_completions on. summary: display values only.
CREATE OR REPLACE PROCEDURE social.pr_emit_activity(
    p_actor_id uuid, p_avatar_type text, p_event_type text, p_summary jsonb DEFAULT '{}'
)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_circle uuid;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM social.circle_share AS s
        INNER JOIN social.circle_member AS m
            ON m.circle_id = s.circle_id AND m.user_id = s.user_id AND m.status = 'active'
        INNER JOIN social.care_circle AS c ON c.id = s.circle_id AND c.deleted_at IS NULL
        WHERE s.user_id = p_actor_id AND s.avatar_type = p_avatar_type
    ) THEN
        RETURN;
    END IF;
    INSERT INTO social.activity_event (actor_id, event_type, avatar_type, summary)
    VALUES (p_actor_id, p_event_type, p_avatar_type, coalesce(p_summary, '{}'));
    IF p_event_type = 'goal_completed' THEN
        FOR v_circle IN
            SELECT s.circle_id FROM social.circle_share AS s
            INNER JOIN social.circle_member AS m
                ON m.circle_id = s.circle_id AND m.user_id = s.user_id AND m.status = 'active'
            INNER JOIN social.care_circle AS c ON c.id = s.circle_id AND c.deleted_at IS NULL
            WHERE s.user_id = p_actor_id AND s.avatar_type = p_avatar_type
        LOOP
            CALL social.pr_notify(
                social.fn_recipients(v_circle, 'goal_completions', p_actor_id), v_circle, 'circles',
                'circle_goal_completed',
                jsonb_build_object('user_id', p_actor_id::text, 'avatar_type', p_avatar_type),
                social.fn_circle_link(v_circle)
            );
        END LOOP;
    END IF;
END
$$;
COMMENT ON PROCEDURE social.pr_emit_activity(uuid, text, text, jsonb) IS
'Internal: feed event for a shared avatar; goal_completed notifies circle members';

REVOKE ALL ON FUNCTION social.fn_require_username(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_is_blocked(uuid, uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_require_member(uuid, uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_require_admin(uuid, uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_validate_shares(uuid, text[]) FROM public;
REVOKE ALL ON PROCEDURE social.pr_apply_shares(uuid, uuid, text[]) FROM public;
REVOKE ALL ON FUNCTION social.fn_recipients(uuid, text, uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_circle_link(uuid, text) FROM public;
REVOKE ALL ON PROCEDURE social.pr_emit_activity(uuid, text, text, jsonb) FROM public;
