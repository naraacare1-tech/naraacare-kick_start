-- Circle chat (doc 04 section 2.9, OQ-35): text + @mentions, delete own message (admins may delete
-- any), no edits, no read receipts. Bodies are plain text validated by common.safe_text (no markup).
--   * Idempotent send: the same (sender, client_message_id) within a day returns the first message
--     (o_status duplicate).
--   * Mentions are member user ids chosen in the app, never parsed from the text; each must be an
--     active member other than the sender and not blocked with them (22023 MENTION_INVALID).
--   * Mentioned members get a 'circle_mention' notification; members who switched on new_messages
--     get 'circle_message'. Notifications never carry the message text (OQ-41).
-- Errors: 42501 not a member / message not found (404), P0001 ADMIN_REQUIRED, 22023 MENTION_INVALID /
--         TOO_MANY_MENTIONS.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE social.pr_post_message(
    p_user_id uuid,
    p_circle_id uuid,
    p_client_message_id uuid,
    p_body common.safe_text,
    p_mention_user_ids uuid[] DEFAULT '{}',
    INOUT o_message_id uuid DEFAULT NULL,
    INOUT o_created_at timestamptz DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_mentions uuid[];
    v_recipients uuid[];
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM social.fn_require_username(p_user_id);
    PERFORM social.fn_require_member(p_circle_id, p_user_id);
    IF p_client_message_id IS NULL THEN
        RAISE EXCEPTION 'client_message_id is required' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('social.chat:' || p_user_id::text || p_client_message_id::text, 0));
    SELECT m.id, m.created_at INTO o_message_id, o_created_at
    FROM social.chat_message AS m
    WHERE m.sender_id = p_user_id AND m.client_message_id = p_client_message_id
      AND m.created_at > now() - interval '1 day';
    IF FOUND THEN
        o_status := 'duplicate';
        RETURN;
    END IF;

    SELECT coalesce(array_agg(DISTINCT u), '{}') INTO v_mentions FROM unnest(coalesce(p_mention_user_ids, '{}')) AS u;
    IF cardinality(v_mentions) > 20 THEN
        RAISE EXCEPTION 'at most 20 mentions' USING ERRCODE = '22023', DETAIL = 'TOO_MANY_MENTIONS';
    END IF;
    IF EXISTS (
        SELECT 1 FROM unnest(v_mentions) AS u
        WHERE u = p_user_id
           OR social.fn_is_blocked(p_user_id, u)
           OR NOT EXISTS (
               SELECT 1 FROM social.circle_member AS m
               WHERE m.circle_id = p_circle_id AND m.user_id = u AND m.status = 'active'
           )
    ) THEN
        RAISE EXCEPTION 'you can only mention members of this circle' USING ERRCODE = '22023', DETAIL = 'MENTION_INVALID';
    END IF;

    INSERT INTO social.chat_message (circle_id, sender_id, client_message_id, body)
    VALUES (p_circle_id, p_user_id, p_client_message_id, btrim(p_body))
    RETURNING id, created_at INTO o_message_id, o_created_at;
    INSERT INTO social.chat_mention (message_id, mentioned_user_id, message_created_at, circle_id)
    SELECT o_message_id, u, o_created_at, p_circle_id FROM unnest(v_mentions) AS u;
    UPDATE social.circle_member SET last_read_at = now() WHERE circle_id = p_circle_id AND user_id = p_user_id;

    IF cardinality(v_mentions) > 0 THEN
        SELECT coalesce(array_agg(r), '{}') INTO v_recipients
        FROM unnest(social.fn_recipients(p_circle_id, 'mentions', p_user_id)) AS r
        WHERE r = ANY (v_mentions);
        CALL social.pr_notify(
            v_recipients, p_circle_id, 'circles', 'circle_mention',
            jsonb_build_object('user_id', p_user_id::text), social.fn_circle_link(p_circle_id, '/chat')
        );
    END IF;
    SELECT coalesce(array_agg(r), '{}') INTO v_recipients
    FROM unnest(social.fn_recipients(p_circle_id, 'new_messages', p_user_id)) AS r
    WHERE NOT r = ANY (v_mentions);
    CALL social.pr_notify(
        v_recipients, p_circle_id, 'circles', 'circle_message', '{}', social.fn_circle_link(p_circle_id, '/chat')
    );
    o_status := 'created';
END
$$;

CREATE OR REPLACE PROCEDURE social.pr_delete_message(p_user_id uuid, p_circle_id uuid, p_message_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_role common.code;
    v_sender uuid;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_role := social.fn_require_member(p_circle_id, p_user_id);
    SELECT m.sender_id INTO v_sender FROM social.chat_message AS m
    WHERE m.id = p_message_id AND m.circle_id = p_circle_id AND m.deleted_at IS NULL;
    IF v_sender IS NULL THEN
        RAISE EXCEPTION 'message not found' USING ERRCODE = '42501';
    END IF;
    IF v_sender <> p_user_id AND v_role <> 'admin' THEN
        RAISE EXCEPTION 'only the sender or an admin can delete this' USING ERRCODE = 'P0001', DETAIL = 'ADMIN_REQUIRED';
    END IF;
    UPDATE social.chat_message SET deleted_at = now(), deleted_by = p_user_id
    WHERE id = p_message_id AND circle_id = p_circle_id;
END
$$;

COMMENT ON PROCEDURE social.pr_post_message(uuid, uuid, uuid, common.safe_text, uuid[], uuid, timestamptz, text) IS
'Send a chat message (idempotent by client id) with member mentions';
COMMENT ON PROCEDURE social.pr_delete_message(uuid, uuid, uuid) IS 'Delete a message (sender or admin)';

REVOKE ALL ON PROCEDURE social.pr_post_message(uuid, uuid, uuid, common.safe_text, uuid[], uuid, timestamptz, text) FROM public;
REVOKE ALL ON PROCEDURE social.pr_delete_message(uuid, uuid, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE social.pr_post_message(uuid, uuid, uuid, common.safe_text, uuid[], uuid, timestamptz, text) TO app_rw;
GRANT EXECUTE ON PROCEDURE social.pr_delete_message(uuid, uuid, uuid) TO app_rw;
