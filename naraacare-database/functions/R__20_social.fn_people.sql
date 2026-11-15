-- People search, suggestions, connections and blocks lists (doc 04 section 2.8, OQ-36).
-- Search: username prefix (>= 3 characters), at most 20, blocked users hidden both ways; it shows
-- only the public card (username, initial, avatar), never names of strangers.
-- Suggestions: people the caller shares a circle with and is not connected to.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Connection state between the caller and others: none | connected | incoming | outgoing.
CREATE OR REPLACE FUNCTION social.fn_connection_state(p_user_id uuid, p_other uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT coalesce((
        SELECT CASE
            WHEN c.status = 'accepted' THEN 'connected'
            WHEN c.status = 'pending' AND c.addressee_id = p_user_id THEN 'incoming'
            ELSE 'outgoing'  -- pending from the caller, or declined (never revealed)
        END
        FROM social.connection AS c
        WHERE c.user_low = least(p_user_id, p_other) AND c.user_high = greatest(p_user_id, p_other)
          AND c.deleted_at IS NULL
          AND NOT (c.status = 'declined' AND c.requester_id = p_other)
    ), 'none')
$$;
COMMENT ON FUNCTION social.fn_connection_state(uuid, uuid) IS 'Internal: none | connected | incoming | outgoing';
REVOKE ALL ON FUNCTION social.fn_connection_state(uuid, uuid) FROM public;

CREATE OR REPLACE FUNCTION social.fn_people_search(p_user_id uuid, p_query text)
RETURNS TABLE (
    user_id uuid,
    username common.username,
    display_initial text,
    avatar_code common.code,
    connection_status text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    IF p_query IS NULL OR char_length(btrim(p_query)) < 3 OR char_length(p_query) > 64 THEN
        RAISE EXCEPTION 'type at least 3 characters' USING ERRCODE = '22023', DETAIL = 'QUERY_TOO_SHORT';
    END IF;
    RETURN QUERY
    WITH f AS (SELECT * FROM social.fn_find_usernames(btrim(ltrim(p_query, '@')), 50))
    SELECT p.user_id, p.username, p.display_initial, p.avatar_code, social.fn_connection_state(p_user_id, p.user_id)
    FROM f
    INNER JOIN social.fn_public_profiles(ARRAY(SELECT f2.user_id FROM f AS f2)) AS p ON p.user_id = f.user_id
    WHERE f.user_id <> p_user_id
      AND NOT social.fn_is_blocked(p_user_id, f.user_id)
    ORDER BY f.username
    LIMIT 20;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_suggestions(p_user_id uuid)
RETURNS TABLE (
    user_id uuid,
    username common.username,
    display_initial text,
    avatar_code common.code,
    shared_circles integer
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
    WITH co AS (
        SELECT other.user_id, count(*)::integer AS n
        FROM social.circle_member AS me
        INNER JOIN social.care_circle AS c ON c.id = me.circle_id AND c.deleted_at IS NULL
        INNER JOIN social.circle_member AS other
            ON other.circle_id = me.circle_id AND other.status = 'active' AND other.user_id <> p_user_id
        WHERE me.user_id = p_user_id AND me.status = 'active'
        GROUP BY other.user_id
    )
    SELECT p.user_id, p.username, p.display_initial, p.avatar_code, co.n
    FROM co
    INNER JOIN social.fn_public_profiles(ARRAY(SELECT co2.user_id FROM co AS co2)) AS p ON p.user_id = co.user_id
    WHERE p.username IS NOT NULL
      AND social.fn_connection_state(p_user_id, co.user_id) = 'none'
      AND NOT social.fn_is_blocked(p_user_id, co.user_id)
    ORDER BY co.n DESC, p.username
    LIMIT 20;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_connections(p_user_id uuid)
RETURNS TABLE (
    connection_id uuid,
    user_id uuid,
    username common.username,
    display_name text,
    display_initial text,
    avatar_code common.code,
    status text,
    since timestamptz
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
    WITH mine AS (
        SELECT
            c.id,
            CASE WHEN c.requester_id = p_user_id THEN c.addressee_id ELSE c.requester_id END AS other,
            CASE
                WHEN c.status = 'accepted' THEN 'connected'
                WHEN c.addressee_id = p_user_id THEN 'incoming'
                ELSE 'outgoing'
            END AS state,
            coalesce(c.responded_at, c.created_at) AS since
        FROM social.connection AS c
        WHERE p_user_id IN (c.requester_id, c.addressee_id)
          AND c.deleted_at IS NULL
          AND (c.status IN ('accepted', 'pending') OR (c.status = 'declined' AND c.requester_id = p_user_id))
    )
    SELECT
        m.id, m.other, p.username,
        -- Names only between connected people; requests show the public card.
        CASE WHEN m.state = 'connected' THEN p.display_name END,
        p.display_initial, p.avatar_code, m.state, m.since
    FROM mine AS m
    INNER JOIN social.fn_public_profiles(ARRAY(SELECT m2.other FROM mine AS m2)) AS p ON p.user_id = m.other
    WHERE NOT social.fn_is_blocked(p_user_id, m.other)
    ORDER BY (m.state = 'incoming') DESC, p.username
    LIMIT 500;
END
$$;

CREATE OR REPLACE FUNCTION social.fn_blocks(p_user_id uuid)
RETURNS TABLE (user_id uuid, username common.username, display_initial text, blocked_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT b.blocked_id, p.username, p.display_initial, b.created_at
    FROM social.user_block AS b
    LEFT JOIN social.fn_public_profiles(
        ARRAY(SELECT b2.blocked_id FROM social.user_block AS b2 WHERE b2.blocker_id = p_user_id)
    ) AS p ON p.user_id = b.blocked_id
    WHERE b.blocker_id = p_user_id
    ORDER BY b.created_at DESC;
END
$$;

COMMENT ON FUNCTION social.fn_people_search(uuid, text) IS 'Username prefix search (>= 3 chars, <= 20, blocks hidden)';
COMMENT ON FUNCTION social.fn_suggestions(uuid) IS 'Circle co-members the caller is not connected to (<= 20)';
COMMENT ON FUNCTION social.fn_connections(uuid) IS 'Connections and pending requests (incoming first)';
COMMENT ON FUNCTION social.fn_blocks(uuid) IS 'Users the caller blocked';

REVOKE ALL ON FUNCTION social.fn_people_search(uuid, text) FROM public;
REVOKE ALL ON FUNCTION social.fn_suggestions(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_connections(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_blocks(uuid) FROM public;
GRANT EXECUTE ON FUNCTION social.fn_people_search(uuid, text) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_suggestions(uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_connections(uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION social.fn_blocks(uuid) TO app_rw;
