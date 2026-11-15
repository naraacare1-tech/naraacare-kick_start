-- Rin AI reads (Session 13, doc 04 section 2.10, doc 06 section 8, OQ-37).
--   * fn_require_rin: onboarding done, STAR (features.rin_ai) and ai_processing consent; returns the
--     user's timezone. Every Rin routine calls it, so the gate holds even if the API forgets.
--   * fn_rin_context: the ONLY data sent to the model: age band, sex, goals, today's and the last 7
--     days' aggregates and the memory summary. Never names, email, exact age or other users.
--   * fn_usage_month: AI spend this local month (micro-rupees) and when the monthly cap resets (V026).
-- Errors: P0001 ONBOARDING_INCOMPLETE / UPGRADE_REQUIRED / CONSENT_REQUIRED, 42501 not found (404).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION ai.fn_require_rin(p_user_id uuid)
RETURNS common.iana_timezone
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_features jsonb;
BEGIN
    SELECT p.timezone INTO v_timezone
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF NOT coalesce((v_features ->> 'rin_ai')::boolean, FALSE) THEN
        RAISE EXCEPTION 'Rin AI needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;
    IF NOT coalesce((
        SELECT c.granted FROM privacy.consent_record AS c
        WHERE c.user_id = p_user_id AND c.purpose = 'ai_processing'
        ORDER BY c.recorded_at DESC, c.id DESC
        LIMIT 1
    ), FALSE) THEN
        RAISE EXCEPTION 'AI consent needed' USING ERRCODE = 'P0001', DETAIL = 'CONSENT_REQUIRED';
    END IF;
    RETURN v_timezone;
END
$$;
COMMENT ON FUNCTION ai.fn_require_rin(uuid) IS 'Internal: onboarding, STAR rin_ai and ai_processing consent; the timezone';
REVOKE ALL ON FUNCTION ai.fn_require_rin(uuid) FROM public;

CREATE OR REPLACE FUNCTION ai.fn_rin_context(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_tz common.iana_timezone;
    v_today date;
    v_result jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_tz := ai.fn_require_rin(p_user_id);
    v_today := common.fn_local_date(v_tz);
    SELECT jsonb_build_object(
        'today', v_today,
        'profile', jsonb_build_object(
            -- An age band, never the exact age (OQ-37 data minimisation).
            'age_band', CASE
                WHEN p.age_years IS NULL THEN NULL
                WHEN p.age_years < 30 THEN '18-29'
                WHEN p.age_years < 45 THEN '30-44'
                WHEN p.age_years < 60 THEN '45-59'
                ELSE '60+'
            END,
            'sex', p.biological_sex,
            'weight_goal', p.weight_goal_code,
            'activity_level', p.activity_level_code,
            'sleep_goal_min', p.sleep_goal_min
        ),
        'water_today', (
            SELECT jsonb_build_object(
                'consumed_ml', round(h.effective_intake_ml)::integer, 'goal_ml', h.daily_need_ml,
                'goal_completed', h.goal_completed_at IS NOT NULL
            )
            FROM hydration.daily_summary AS h WHERE h.user_id = p_user_id AND h.local_date = v_today
        ),
        'food_today', (
            SELECT jsonb_build_object(
                'kcal', round(n.calories_kcal_total)::integer, 'allowance_kcal', n.effective_allowance_kcal,
                'protein_g', round(n.protein_g_total)::integer, 'carbs_g', round(n.carbohydrates_g_total)::integer,
                'fat_g', round(n.fat_g_total)::integer, 'meals', n.meal_count
            )
            FROM nutrition.daily_summary AS n WHERE n.user_id = p_user_id AND n.local_date = v_today
        ),
        'sleep_today', (
            SELECT jsonb_build_object('counted_min', s.counted_min, 'score_pct', s.score_pct)
            FROM sleep.daily_summary AS s WHERE s.user_id = p_user_id AND s.local_date = v_today
        ),
        'last_7_days', jsonb_build_object(
            'avg_water_ml', (
                SELECT round(avg(h.effective_intake_ml))::integer FROM hydration.daily_summary AS h
                WHERE h.user_id = p_user_id AND h.local_date BETWEEN v_today - 7 AND v_today - 1
            ),
            'water_goal_days', (
                SELECT count(*) FILTER (WHERE h.goal_completed_at IS NOT NULL)::integer
                FROM hydration.daily_summary AS h
                WHERE h.user_id = p_user_id AND h.local_date BETWEEN v_today - 7 AND v_today - 1
            ),
            'avg_kcal', (
                SELECT round(avg(n.calories_kcal_total))::integer FROM nutrition.daily_summary AS n
                WHERE n.user_id = p_user_id AND n.local_date BETWEEN v_today - 7 AND v_today - 1
                  AND n.meal_count > 0
            ),
            'avg_sleep_min', (
                SELECT round(avg(s.counted_min))::integer FROM sleep.daily_summary AS s
                WHERE s.user_id = p_user_id AND s.local_date BETWEEN v_today - 7 AND v_today - 1
                  AND s.counted_min > 0
            )
        ),
        'memory', (SELECT m.summary FROM ai.memory_summary AS m WHERE m.user_id = p_user_id)
    )
    INTO v_result
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id;
    RETURN jsonb_strip_nulls(v_result);
END
$$;

CREATE OR REPLACE FUNCTION ai.fn_usage_month(p_user_id uuid)
RETURNS TABLE (used_micro_inr bigint, month_start date, resets_at timestamptz, next_local_midnight timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_tz text;
    v_today date;
    v_month date;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT coalesce(p.timezone, 'Asia/Kolkata') INTO v_tz FROM app.user_profile AS p WHERE p.user_id = p_user_id;
    v_tz := coalesce(v_tz, 'Asia/Kolkata');
    v_today := common.fn_local_date(v_tz);
    v_month := date_trunc('month', v_today)::date;
    RETURN QUERY
    SELECT
        coalesce(sum(u.cost_micro_inr), 0)::bigint,
        v_month,
        ((v_month + interval '1 month')::timestamp AT TIME ZONE v_tz),
        ((v_today + 1)::timestamp AT TIME ZONE v_tz)
    FROM ai.usage_event AS u
    WHERE u.user_id = p_user_id AND u.local_date >= v_month;
END
$$;

CREATE OR REPLACE FUNCTION ai.fn_conversations(
    p_user_id uuid, p_query text DEFAULT NULL, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 30
)
RETURNS TABLE (conversation_id uuid, title common.safe_text, last_message_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    IF p_query IS NOT NULL AND char_length(p_query) > 64 THEN
        RAISE EXCEPTION 'search text too long' USING ERRCODE = '22023', DETAIL = 'SEARCH_QUERY_INVALID';
    END IF;
    RETURN QUERY
    SELECT c.id, c.title, c.last_message_at
    FROM ai.conversation AS c
    WHERE c.user_id = p_user_id AND c.deleted_at IS NULL
      AND (p_before IS NULL OR c.last_message_at < p_before)
      AND (
          p_query IS NULL OR btrim(p_query) = ''
          -- Title or any prompt of the chat contains the text (escaped LIKE, case-insensitive).
          OR c.title ILIKE '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
          OR EXISTS (
              SELECT 1 FROM ai.message AS m
              WHERE m.conversation_id = c.id AND m.role = 'user'
                AND m.content ILIKE '%' || replace(replace(replace(btrim(p_query), '\', '\\'), '%', '\%'), '_', '\_') || '%'
          )
      )
    ORDER BY c.last_message_at DESC
    LIMIT least(greatest(coalesce(p_limit, 30), 1), 50);
END
$$;

CREATE OR REPLACE FUNCTION ai.fn_messages(
    p_user_id uuid, p_conversation_id uuid, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 50
)
RETURNS TABLE (
    message_id uuid,
    role common.code,
    content common.safe_text,
    created_at timestamptz,
    action jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    IF NOT EXISTS (
        SELECT 1 FROM ai.conversation AS c
        WHERE c.id = p_conversation_id AND c.user_id = p_user_id AND c.deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'conversation not found' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT m.id, m.role, m.content, m.created_at,
        CASE WHEN a.id IS NULL THEN NULL ELSE jsonb_build_object(
            'action_id', a.id, 'kind', a.kind, 'payload', a.payload,
            'status', CASE WHEN a.status = 'pending' AND a.expires_at <= now() THEN 'expired' ELSE a.status END
        ) END
    FROM ai.message AS m
    LEFT JOIN ai.pending_action AS a ON a.id = m.action_id
    WHERE m.conversation_id = p_conversation_id AND m.user_id = p_user_id
      AND (p_before IS NULL OR m.created_at < p_before)
    ORDER BY m.created_at DESC
    LIMIT least(greatest(coalesce(p_limit, 50), 1), 100);
END
$$;

-- Recent turns for the model (oldest first), capped by count; used to build the request.
CREATE OR REPLACE FUNCTION ai.fn_history(p_user_id uuid, p_conversation_id uuid, p_limit integer DEFAULT 20)
RETURNS TABLE (role common.code, content common.safe_text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT t.role, t.content FROM (
        SELECT m.role, m.content, m.created_at
        FROM ai.message AS m
        WHERE m.conversation_id = p_conversation_id AND m.user_id = p_user_id
        ORDER BY m.created_at DESC
        LIMIT least(greatest(coalesce(p_limit, 20), 1), 40)
    ) AS t
    ORDER BY t.created_at;
END
$$;

CREATE OR REPLACE FUNCTION ai.fn_pending_action(p_user_id uuid, p_action_id uuid)
RETURNS TABLE (
    action_id uuid,
    kind common.code,
    payload jsonb,
    status common.code,
    expired boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM ai.fn_require_rin(p_user_id);
    RETURN QUERY
    SELECT a.id, a.kind, a.payload, a.status, a.expires_at <= now()
    FROM ai.pending_action AS a
    WHERE a.id = p_action_id AND a.user_id = p_user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'action not found' USING ERRCODE = '42501';
    END IF;
END
$$;

COMMENT ON FUNCTION ai.fn_rin_context(uuid) IS 'The data Rin may see: own profile band, today, last 7 days, memory';
COMMENT ON FUNCTION ai.fn_usage_month(uuid) IS 'AI spend this local month in micro-rupees (all AI features), the reset time and the next local midnight';
COMMENT ON FUNCTION ai.fn_conversations(uuid, text, timestamptz, integer) IS 'Rin chats, newest first, optional text search';
COMMENT ON FUNCTION ai.fn_messages(uuid, uuid, timestamptz, integer) IS 'A Rin chat, newest first, with action cards';
COMMENT ON FUNCTION ai.fn_history(uuid, uuid, integer) IS 'Recent turns of a Rin chat for the model, oldest first';
COMMENT ON FUNCTION ai.fn_pending_action(uuid, uuid) IS 'One proposed log of the caller';

REVOKE ALL ON FUNCTION ai.fn_rin_context(uuid) FROM public;
REVOKE ALL ON FUNCTION ai.fn_usage_month(uuid) FROM public;
REVOKE ALL ON FUNCTION ai.fn_conversations(uuid, text, timestamptz, integer) FROM public;
REVOKE ALL ON FUNCTION ai.fn_messages(uuid, uuid, timestamptz, integer) FROM public;
REVOKE ALL ON FUNCTION ai.fn_history(uuid, uuid, integer) FROM public;
REVOKE ALL ON FUNCTION ai.fn_pending_action(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION ai.fn_rin_context(uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION ai.fn_usage_month(uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION ai.fn_conversations(uuid, text, timestamptz, integer) TO app_rw;
GRANT EXECUTE ON FUNCTION ai.fn_messages(uuid, uuid, timestamptz, integer) TO app_rw;
GRANT EXECUTE ON FUNCTION ai.fn_history(uuid, uuid, integer) TO app_rw;
GRANT EXECUTE ON FUNCTION ai.fn_pending_action(uuid, uuid) TO app_rw;
