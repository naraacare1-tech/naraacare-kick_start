-- Connections and blocks (doc 04 section 2.8, doc 06 section 7, OQ-36). Username required for every
-- action. A block hides the pair from each other both ways and ends their connection.
--   * pr_request_connection(username): o_status pending | accepted (they had already asked you) |
--     already_connected. Unknown or blocked usernames raise 42501 (404: no way to probe blocks).
--     A request the other person declined stays silently pending for the requester.
--   * pr_respond_connection(id, accept): only the addressee of a pending request.
--   * pr_remove_connection(id): either side; removes a connection or cancels a request.
--   * pr_block / pr_unblock (idempotent).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE social.pr_request_connection(
    p_user_id uuid,
    p_username common.username,
    INOUT o_connection_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_target uuid;
    v_row social.connection%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    SELECT f.user_id INTO v_target FROM social.fn_find_usernames(p_username, 1) AS f WHERE f.username = p_username;
    IF v_target IS NULL OR social.fn_is_blocked(p_user_id, v_target) THEN
        RAISE EXCEPTION 'user not found' USING ERRCODE = '42501';
    END IF;
    IF v_target = p_user_id THEN
        RAISE EXCEPTION 'you cannot connect with yourself' USING ERRCODE = '22023', DETAIL = 'INVALID_TARGET';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended('social.connection:' || least(p_user_id, v_target)::text || greatest(p_user_id, v_target)::text, 0)
    );
    SELECT * INTO v_row FROM social.connection AS c
    WHERE c.user_low = least(p_user_id, v_target) AND c.user_high = greatest(p_user_id, v_target)
      AND c.deleted_at IS NULL
    FOR UPDATE;

    IF FOUND THEN
        o_connection_id := v_row.id;
        IF v_row.status = 'accepted' THEN
            o_status := 'already_connected';
        ELSIF v_row.status = 'pending' AND v_row.addressee_id = p_user_id THEN
            UPDATE social.connection SET status = 'accepted', responded_at = now() WHERE id = v_row.id;
            CALL social.pr_notify(ARRAY[v_target], NULL, 'connections', 'connection_accepted', '{}', 'naraacare://connections');
            o_status := 'accepted';
        ELSIF v_row.status = 'declined' AND v_row.addressee_id = p_user_id THEN
            -- The person who declined now asks: a fresh request in the other direction.
            UPDATE social.connection
            SET requester_id = p_user_id, addressee_id = v_target, status = 'pending', responded_at = NULL
            WHERE id = v_row.id;
            CALL social.pr_notify(ARRAY[v_target], NULL, 'connections', 'connection_request', '{}', 'naraacare://connections');
            o_status := 'pending';
        ELSE
            o_status := 'pending';  -- already asked (or declined, which the requester is not told)
        END IF;
        RETURN;
    END IF;

    INSERT INTO social.connection (requester_id, addressee_id) VALUES (p_user_id, v_target)
    RETURNING id INTO o_connection_id;
    CALL social.pr_notify(ARRAY[v_target], NULL, 'connections', 'connection_request', '{}', 'naraacare://connections');
    o_status := 'pending';
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_respond_connection(p_user_id uuid, p_connection_id uuid, p_accept boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_requester uuid;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    UPDATE social.connection
    SET status = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END, responded_at = now()
    WHERE id = p_connection_id AND addressee_id = p_user_id AND status = 'pending' AND deleted_at IS NULL
    RETURNING requester_id INTO v_requester;
    IF v_requester IS NULL THEN
        RAISE EXCEPTION 'request not found' USING ERRCODE = '42501';
    END IF;
    IF p_accept THEN
        CALL social.pr_notify(ARRAY[v_requester], NULL, 'connections', 'connection_accepted', '{}', 'naraacare://connections');
    END IF;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_remove_connection(p_user_id uuid, p_connection_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE social.connection SET deleted_at = now()
    WHERE id = p_connection_id
      AND p_user_id IN (requester_id, addressee_id)
      AND status IN ('pending', 'accepted')
      AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'connection not found' USING ERRCODE = '42501';
    END IF;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_block(p_user_id uuid, p_blocked_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_blocked_id = p_user_id THEN
        RAISE EXCEPTION 'you cannot block yourself' USING ERRCODE = '22023', DETAIL = 'INVALID_TARGET';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM social.fn_public_profiles(ARRAY[p_blocked_id])) THEN
        RAISE EXCEPTION 'user not found' USING ERRCODE = '42501';
    END IF;
    INSERT INTO social.user_block (blocker_id, blocked_id) VALUES (p_user_id, p_blocked_id)
    ON CONFLICT DO NOTHING;
    UPDATE social.connection SET deleted_at = now()
    WHERE user_low = least(p_user_id, p_blocked_id) AND user_high = greatest(p_user_id, p_blocked_id)
      AND deleted_at IS NULL;
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_unblock(p_user_id uuid, p_blocked_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    DELETE FROM social.user_block WHERE blocker_id = p_user_id AND blocked_id = p_blocked_id;
END
$$;

COMMENT ON PROCEDURE social.pr_request_connection(uuid, common.username, uuid, text) IS
'Send a connection request by username: pending | accepted | already_connected';
COMMENT ON PROCEDURE social.pr_respond_connection(uuid, uuid, boolean) IS 'Accept or decline an incoming request';
COMMENT ON PROCEDURE social.pr_remove_connection(uuid, uuid) IS 'Remove a connection or cancel a request (either side)';
COMMENT ON PROCEDURE social.pr_block(uuid, uuid) IS 'Block a user (hidden both ways; ends the connection)';
COMMENT ON PROCEDURE social.pr_unblock(uuid, uuid) IS 'Remove a block';

REVOKE ALL ON PROCEDURE social.pr_request_connection(uuid, common.username, uuid, text) FROM public;
REVOKE ALL ON PROCEDURE social.pr_respond_connection(uuid, uuid, boolean) FROM public;
REVOKE ALL ON PROCEDURE social.pr_remove_connection(uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE social.pr_block(uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE social.pr_unblock(uuid, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE social.pr_request_connection(uuid, common.username, uuid, text) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_respond_connection(uuid, uuid, boolean) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_remove_connection(uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_block(uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_unblock(uuid, uuid) TO app_rw;
