-- Cross-user reads for the social layer (Session 12; doc 05 section 7 owner-run allow-list).
-- Profiles, summaries and notifications are protected by own-row RLS, but circles must show other
-- people's username/avatar and, when shared, today's avatar values. These helpers are owned by
-- migration_owner (the table owner: RLS does not apply), return only the fields listed here, and
-- are executable by api_definer alone. Every API routine that calls them checks membership,
-- sharing and blocks first; fn_avatar_state itself never decides visibility.
-- No SET ROLE: created by migration_owner on purpose.

-- Public card: what other users may see about someone (no health data, no email).
CREATE OR REPLACE FUNCTION social.fn_public_profiles(p_user_ids uuid[])
RETURNS TABLE (
    user_id uuid,
    username common.username,
    display_name text,
    display_initial text,
    avatar_code common.code
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        a.id,
        p.username,
        p.full_name::text,
        upper(left(coalesce(nullif(p.full_name::text, ''), p.username::text, '?'), 1)),
        p.avatar_code
    FROM auth.user_account AS a
    LEFT JOIN app.user_profile AS p ON p.user_id = a.id AND p.deleted_at IS NULL
    WHERE a.id = ANY (p_user_ids)
      AND a.status IN ('active', 'locked')
$$;
COMMENT ON FUNCTION social.fn_public_profiles(uuid[]) IS
'Internal (owner-run): username, name, initial and avatar of users; no health data';

-- Username lookup for connection requests and search (exact or prefix; active accounts only).
CREATE OR REPLACE FUNCTION social.fn_find_usernames(p_prefix text, p_limit integer)
RETURNS TABLE (user_id uuid, username common.username)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT p.user_id, p.username
    FROM app.user_profile AS p
    INNER JOIN auth.user_account AS a ON a.id = p.user_id AND a.status = 'active'
    WHERE p.username IS NOT NULL
      AND p.deleted_at IS NULL
      AND p.username::text LIKE replace(replace(replace(lower(p_prefix), '\', '\\'), '%', '\%'), '_', '\_') || '%'
    ORDER BY p.username
    LIMIT least(greatest(p_limit, 1), 50)
$$;
COMMENT ON FUNCTION social.fn_find_usernames(text, integer) IS
'Internal (owner-run): active users whose username starts with the prefix (LIKE-escaped)';

-- Seats used: active members plus open invites (doc 06 section 7, max 50). Owner-run because an
-- invitee accepting cannot see the other members' rows yet.
CREATE OR REPLACE FUNCTION social.fn_seats_taken(p_circle_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT count(*)::integer FROM social.circle_member AS m
    WHERE m.circle_id = p_circle_id AND m.status IN ('active', 'invited', 'maybe_later')
$$;
COMMENT ON FUNCTION social.fn_seats_taken(uuid) IS 'Internal (owner-run): active members + open invites';

-- STAR right now (store subscription or grant), for sharing and viewing the Sleep avatar.
-- Same candidates as billing.fn_current_entitlement, without its actor check.
CREATE OR REPLACE FUNCTION social.fn_is_star(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM billing.subscription AS s
        INNER JOIN billing.store_product AS p ON p.platform = s.platform AND p.product_id = s.product_id
        WHERE s.user_id = p_user_id
          AND s.deleted_at IS NULL
          AND p.tier_code = 'star'
          AND ((s.status IN ('active', 'canceled') AND s.current_period_end > now()) OR s.status = 'in_grace')
    ) OR EXISTS (
        SELECT 1
        FROM billing.entitlement_grant AS g
        WHERE g.user_id = p_user_id
          AND g.deleted_at IS NULL
          AND g.tier_code = 'star'
          AND now() >= g.starts_at
          AND now() < g.ends_at
    )
$$;
COMMENT ON FUNCTION social.fn_is_star(uuid) IS 'Internal (owner-run): the user has STAR now';

-- Today's values of one avatar (the owner's local day). Callers check visibility first.
CREATE OR REPLACE FUNCTION social.fn_avatar_state(p_user_id uuid, p_avatar_type text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_today date;
    v_state jsonb;
BEGIN
    SELECT common.fn_local_date(p.timezone) INTO v_today
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.deleted_at IS NULL;
    IF v_today IS NULL THEN
        RETURN NULL;
    END IF;

    IF p_avatar_type = 'hydration' THEN
        SELECT jsonb_build_object(
            'consumed_ml', round(d.effective_intake_ml)::integer,
            'goal_ml', d.daily_need_ml,
            'pct', CASE WHEN d.daily_need_ml > 0
                THEN least(100, round(100 * d.effective_intake_ml / d.daily_need_ml))::integer END,
            'goal_completed', d.goal_completed_at IS NOT NULL
        ) INTO v_state
        FROM hydration.daily_summary AS d
        WHERE d.user_id = p_user_id AND d.local_date = v_today;
    ELSIF p_avatar_type = 'nutrition' THEN
        SELECT jsonb_build_object(
            'kcal', round(d.calories_kcal_total)::integer,
            'allowance_kcal', d.effective_allowance_kcal,
            'pct', CASE WHEN d.effective_allowance_kcal > 0
                THEN least(100, round(100 * d.calories_kcal_total / d.effective_allowance_kcal))::integer END
        ) INTO v_state
        FROM nutrition.daily_summary AS d
        WHERE d.user_id = p_user_id AND d.local_date = v_today;
    ELSIF p_avatar_type = 'sleep' THEN
        SELECT jsonb_build_object('counted_min', d.counted_min, 'goal_min', d.goal_min, 'score_pct', d.score_pct)
        INTO v_state
        FROM sleep.daily_summary AS d
        WHERE d.user_id = p_user_id AND d.local_date = v_today;
    ELSE
        RAISE EXCEPTION 'unknown avatar type' USING ERRCODE = '22023', DETAIL = 'INVALID_AVATAR';
    END IF;
    RETURN coalesce(v_state, '{}'::jsonb) || jsonb_build_object('local_date', v_today);
END
$$;
COMMENT ON FUNCTION social.fn_avatar_state(uuid, text) IS
'Internal (owner-run): today''s values of one avatar; visibility is checked by the caller';

-- In-app notifications for other users (notify.notification is own-row RLS). params: codes and
-- numbers only (the same rule as security events), so no user text reaches a notification.
CREATE OR REPLACE PROCEDURE social.pr_notify(
    p_user_ids uuid[],
    p_circle_id uuid,
    p_category common.code,
    p_template_code common.code,
    p_params jsonb,
    p_deep_link common.deep_link
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF jsonb_typeof(coalesce(p_params, '{}')) <> 'object' OR EXISTS (
        SELECT 1 FROM jsonb_each(coalesce(p_params, '{}')) AS e
        WHERE e.key !~ '^[a-z][a-z0-9_]{0,62}$'
           OR jsonb_typeof(e.value) NOT IN ('number', 'boolean', 'null', 'string')
           OR (jsonb_typeof(e.value) = 'string'
               AND (e.value #>> '{}') !~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$')
    ) THEN
        RAISE EXCEPTION 'notification params may only hold codes, ids and numbers'
            USING ERRCODE = '22023', DETAIL = 'INVALID_PARAMS';
    END IF;
    INSERT INTO notify.notification (user_id, circle_id, category, template_code, params, deep_link)
    SELECT u, p_circle_id, p_category, p_template_code, coalesce(p_params, '{}'), p_deep_link
    FROM (SELECT DISTINCT unnest(p_user_ids) AS u) AS t
    WHERE u IS NOT NULL;
END
$$;
COMMENT ON PROCEDURE social.pr_notify(uuid[], uuid, common.code, common.code, jsonb, common.deep_link) IS
'Internal (owner-run): in-app notification rows for the given users (params: codes/ids/numbers)';

REVOKE ALL ON FUNCTION social.fn_public_profiles(uuid[]) FROM public;
REVOKE ALL ON FUNCTION social.fn_find_usernames(text, integer) FROM public;
REVOKE ALL ON FUNCTION social.fn_is_star(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_seats_taken(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_avatar_state(uuid, text) FROM public;
REVOKE ALL ON PROCEDURE social.pr_notify(uuid[], uuid, common.code, common.code, jsonb, common.deep_link) FROM public;
GRANT EXECUTE ON FUNCTION social.fn_public_profiles(uuid[]) TO api_definer;
GRANT EXECUTE ON FUNCTION social.fn_find_usernames(text, integer) TO api_definer;
GRANT EXECUTE ON FUNCTION social.fn_is_star(uuid) TO api_definer;
GRANT EXECUTE ON FUNCTION social.fn_seats_taken(uuid) TO api_definer;
GRANT EXECUTE ON FUNCTION social.fn_avatar_state(uuid, text) TO api_definer;
GRANT EXECUTE ON PROCEDURE social.pr_notify(uuid[], uuid, common.code, common.code, jsonb, common.deep_link)
TO api_definer;
