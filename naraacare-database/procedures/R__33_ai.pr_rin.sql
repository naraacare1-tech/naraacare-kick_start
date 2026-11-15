-- Rin AI writes (Session 13, doc 04 section 2.10, doc 06 section 8).
--   * pr_create_conversation: a new chat titled from the first prompt.
--   * pr_append_message: a user prompt (idempotent by client_message_id: o_status duplicate) or a
--     model reply; text is common.safe_text (the API sanitises model output to plain text first).
--   * pr_record_usage: one model call's token counts and its cost in micro-rupees (monthly cap, V026).
--   * pr_create_pending_action / pr_resolve_pending_action: a proposed meal or drink; it is only
--     logged when the user accepts (the API then calls the normal meal/intake procedures with
--     source 'rin' and records the result id here). Actions expire after 24 h.
--   * pr_delete_conversation (soft), pr_upsert_memory, pr_delete_memory.
-- Errors: 42501 not found (404), P0001 ACTION_RESOLVED (409) / ACTION_EXPIRED (410), plus the
--         fn_require_rin gate (UPGRADE_REQUIRED / CONSENT_REQUIRED / ONBOARDING_INCOMPLETE).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE ai.pr_create_conversation(
    p_user_id uuid,
    p_title common.safe_text,
    INOUT o_conversation_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    INSERT INTO ai.conversation (user_id, title, created_by, updated_by)
    VALUES (p_user_id, left(btrim(p_title), 80), p_user_id, p_user_id)
    RETURNING id INTO o_conversation_id;
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_append_message(
    p_user_id uuid,
    p_conversation_id uuid,
    p_role text,
    p_content common.safe_text,
    p_client_message_id uuid DEFAULT NULL,
    p_action_id uuid DEFAULT NULL,
    INOUT o_message_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    IF p_role NOT IN ('user', 'assistant') THEN
        RAISE EXCEPTION 'unknown role' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    PERFORM 1 FROM ai.conversation AS c
    WHERE c.id = p_conversation_id AND c.user_id = p_user_id AND c.deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'conversation not found' USING ERRCODE = '42501';
    END IF;
    IF p_role = 'user' THEN
        SELECT m.id INTO o_message_id FROM ai.message AS m
        WHERE m.user_id = p_user_id AND m.client_message_id = p_client_message_id;
        IF FOUND THEN
            o_status := 'duplicate';
            RETURN;
        END IF;
    END IF;
    IF p_action_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM ai.pending_action AS a WHERE a.id = p_action_id AND a.user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'action not found' USING ERRCODE = '42501';
    END IF;
    INSERT INTO ai.message (conversation_id, user_id, role, content, client_message_id, action_id)
    VALUES (
        p_conversation_id, p_user_id, p_role, btrim(p_content),
        CASE WHEN p_role = 'user' THEN p_client_message_id END, p_action_id
    )
    RETURNING id INTO o_message_id;
    UPDATE ai.conversation SET
        last_message_at = now(), updated_at = now(), updated_by = p_user_id,
        -- A new chat takes its title from the first prompt (first line, 60 characters).
        title = CASE
            WHEN p_role = 'user' AND title = 'New chat'
                THEN coalesce(nullif(left(btrim(regexp_replace(split_part(btrim(p_content), E'\n', 1), '\s+', ' ', 'g')), 60), ''), title)
            ELSE title
        END
    WHERE id = p_conversation_id;
    o_status := 'created';
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_record_usage(
    p_user_id uuid,
    p_feature text,
    p_model text,
    p_input_tokens integer,
    p_output_tokens integer,
    p_cache_write_tokens integer DEFAULT 0,
    p_cache_read_tokens integer DEFAULT 0,
    p_cost_micro_inr bigint DEFAULT 0
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_tz common.iana_timezone;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT p.timezone INTO v_tz FROM app.user_profile AS p WHERE p.user_id = p_user_id;
    INSERT INTO ai.usage_event (
        user_id, local_date, feature, model, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens,
        cost_micro_inr
    ) VALUES (
        p_user_id, common.fn_local_date(coalesce(v_tz, 'Asia/Kolkata')), p_feature, p_model,
        greatest(p_input_tokens, 0), greatest(p_output_tokens, 0),
        greatest(coalesce(p_cache_write_tokens, 0), 0), greatest(coalesce(p_cache_read_tokens, 0), 0),
        greatest(coalesce(p_cost_micro_inr, 0), 0)
    );
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_create_pending_action(
    p_user_id uuid,
    p_conversation_id uuid,
    p_kind text,
    p_payload jsonb,
    INOUT o_action_id uuid DEFAULT NULL,
    INOUT o_expires_at timestamptz DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    IF p_kind NOT IN ('meal', 'drink') OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
        RAISE EXCEPTION 'invalid action' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    IF p_conversation_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM ai.conversation AS c WHERE c.id = p_conversation_id AND c.user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'conversation not found' USING ERRCODE = '42501';
    END IF;
    INSERT INTO ai.pending_action (user_id, conversation_id, kind, payload, expires_at)
    VALUES (p_user_id, p_conversation_id, p_kind, p_payload, now() + interval '24 hours')
    RETURNING id, expires_at INTO o_action_id, o_expires_at;
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_resolve_pending_action(
    p_user_id uuid,
    p_action_id uuid,
    p_status text,
    p_result_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_action ai.pending_action%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    IF p_status NOT IN ('accepted', 'dismissed') THEN
        RAISE EXCEPTION 'invalid status' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    SELECT * INTO v_action FROM ai.pending_action AS a
    WHERE a.id = p_action_id AND a.user_id = p_user_id
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'action not found' USING ERRCODE = '42501';
    END IF;
    IF v_action.status <> 'pending' THEN
        RAISE EXCEPTION 'already resolved' USING ERRCODE = 'P0001', DETAIL = 'ACTION_RESOLVED';
    END IF;
    IF p_status = 'accepted' AND v_action.expires_at <= now() THEN
        RAISE EXCEPTION 'this suggestion has expired' USING ERRCODE = 'P0001', DETAIL = 'ACTION_EXPIRED';
    END IF;
    UPDATE ai.pending_action SET status = p_status, result_id = p_result_id, resolved_at = now()
    WHERE id = p_action_id;
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_delete_conversation(p_user_id uuid, p_conversation_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE ai.conversation SET deleted_at = now(), updated_at = now(), updated_by = p_user_id
    WHERE id = p_conversation_id AND user_id = p_user_id AND deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'conversation not found' USING ERRCODE = '42501';
    END IF;
    -- The texts go at once; only the soft-deleted header stays for audit (purged with the account).
    DELETE FROM ai.message WHERE conversation_id = p_conversation_id AND user_id = p_user_id;
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_upsert_memory(p_user_id uuid, p_summary common.safe_text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    INSERT INTO ai.memory_summary (user_id, summary) VALUES (p_user_id, left(btrim(p_summary), 2000))
    ON CONFLICT (user_id) DO UPDATE SET summary = excluded.summary, updated_at = now();
END
$$;

CREATE OR REPLACE PROCEDURE ai.pr_delete_memory(p_user_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    DELETE FROM ai.memory_summary WHERE user_id = p_user_id;
END
$$;

COMMENT ON PROCEDURE ai.pr_create_conversation(uuid, common.safe_text, uuid) IS 'New Rin chat';
COMMENT ON PROCEDURE ai.pr_append_message(uuid, uuid, text, common.safe_text, uuid, uuid, uuid, text) IS
'Add a prompt (idempotent by client id) or a plain-text reply to a Rin chat';
COMMENT ON PROCEDURE ai.pr_record_usage(uuid, text, text, integer, integer, integer, integer, bigint) IS
'Record one model call''s tokens';
COMMENT ON PROCEDURE ai.pr_create_pending_action(uuid, uuid, text, jsonb, uuid, timestamptz) IS
'Store a log Rin proposed (24 h)';
COMMENT ON PROCEDURE ai.pr_resolve_pending_action(uuid, uuid, text, uuid) IS 'Accept or dismiss a proposed log';
COMMENT ON PROCEDURE ai.pr_delete_conversation(uuid, uuid) IS 'Delete a Rin chat (messages removed)';
COMMENT ON PROCEDURE ai.pr_upsert_memory(uuid, common.safe_text) IS 'Save the Rin memory summary';
COMMENT ON PROCEDURE ai.pr_delete_memory(uuid) IS 'Clear the Rin memory summary';

REVOKE ALL ON PROCEDURE ai.pr_create_conversation(uuid, common.safe_text, uuid) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_append_message(uuid, uuid, text, common.safe_text, uuid, uuid, uuid, text) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_record_usage(uuid, text, text, integer, integer, integer, integer, bigint) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_create_pending_action(uuid, uuid, text, jsonb, uuid, timestamptz) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_resolve_pending_action(uuid, uuid, text, uuid) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_delete_conversation(uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_upsert_memory(uuid, common.safe_text) FROM public;
REVOKE ALL ON PROCEDURE ai.pr_delete_memory(uuid) FROM public;
GRANT EXECUTE ON PROCEDURE ai.pr_create_conversation(uuid, common.safe_text, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_append_message(uuid, uuid, text, common.safe_text, uuid, uuid, uuid, text) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_record_usage(uuid, text, text, integer, integer, integer, integer, bigint) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_create_pending_action(uuid, uuid, text, jsonb, uuid, timestamptz) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_resolve_pending_action(uuid, uuid, text, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_delete_conversation(uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_upsert_memory(uuid, common.safe_text) TO app_rw;
GRANT EXECUTE ON PROCEDURE ai.pr_delete_memory(uuid) TO app_rw;
