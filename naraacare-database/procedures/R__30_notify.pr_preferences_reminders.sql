-- GET/PUT /me/notification-preferences and GET/PUT /me/reminders (doc 04 section 2.7).
--   * Preferences: the 12 toggles of Figma Notification Settings. PUT replaces all of them: every
--     key must be present and boolean, unknown keys are rejected (22023), never ignored.
--   * Reminders: one schedule per type (hydration, nutrition, sleep, daily_checkin, health_profile),
--     times in the user's local time ("HH:MM", at most 12, distinct) or an interval of 60..240 min
--     (from wake time to bedtime). Types never saved come back disabled with suggested times, so
--     reminders are opt-in after the permission explainer.
-- Errors: 42501 not the actor, 22023 invalid payload.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION notify.fn_notification_preferences(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row notify.notification_preference%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_row FROM notify.notification_preference AS p WHERE p.user_id = p_user_id;
    IF NOT FOUND THEN
        -- Column defaults (doc 05) for a user who never changed a toggle.
        v_row := ROW(
            p_user_id, TRUE, TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE, NULL
        )::notify.notification_preference;
    END IF;
    RETURN to_jsonb(v_row) - 'user_id' - 'updated_at';
END
$$;

COMMENT ON FUNCTION notify.fn_notification_preferences(uuid) IS
'The caller''s 12 notification toggles (defaults when never saved)';
REVOKE ALL ON FUNCTION notify.fn_notification_preferences(uuid) FROM public;
GRANT EXECUTE ON FUNCTION notify.fn_notification_preferences(uuid) TO app_rw;

CREATE OR REPLACE PROCEDURE notify.pr_set_notification_preferences(p_user_id uuid, p_preferences jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_keys constant text[] := ARRAY[
        'goal_completions', 'streak_milestones', 'health_insights', 'hydration_reminders',
        'nutrition_reminders', 'sleep_reminders', 'daily_checkin', 'health_profile_reminders',
        'connection_requests', 'connection_activity', 'reports_ready', 'subscription_payments'
    ];
    v_key text;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_preferences IS NULL OR jsonb_typeof(p_preferences) <> 'object' THEN
        RAISE EXCEPTION 'preferences must be an object' USING ERRCODE = '22023', DETAIL = 'PREFERENCES_INVALID';
    END IF;
    FOR v_key IN SELECT jsonb_object_keys(p_preferences) LOOP
        IF NOT v_key = ANY (v_keys) THEN
            RAISE EXCEPTION 'unknown preference' USING ERRCODE = '22023', DETAIL = 'PREFERENCES_INVALID';
        END IF;
    END LOOP;
    FOREACH v_key IN ARRAY v_keys LOOP
        IF jsonb_typeof(p_preferences -> v_key) IS DISTINCT FROM 'boolean' THEN
            RAISE EXCEPTION 'every preference must be true or false'
                USING ERRCODE = '22023', DETAIL = 'PREFERENCES_INVALID';
        END IF;
    END LOOP;

    INSERT INTO notify.notification_preference AS p (
        user_id, goal_completions, streak_milestones, health_insights, hydration_reminders,
        nutrition_reminders, sleep_reminders, daily_checkin, health_profile_reminders,
        connection_requests, connection_activity, reports_ready, subscription_payments
    )
    SELECT
        p_user_id, r.goal_completions, r.streak_milestones, r.health_insights, r.hydration_reminders,
        r.nutrition_reminders, r.sleep_reminders, r.daily_checkin, r.health_profile_reminders,
        r.connection_requests, r.connection_activity, r.reports_ready, r.subscription_payments
    FROM jsonb_populate_record(NULL::notify.notification_preference, p_preferences) AS r
    ON CONFLICT (user_id) DO UPDATE SET
        goal_completions = excluded.goal_completions, streak_milestones = excluded.streak_milestones,
        health_insights = excluded.health_insights, hydration_reminders = excluded.hydration_reminders,
        nutrition_reminders = excluded.nutrition_reminders, sleep_reminders = excluded.sleep_reminders,
        daily_checkin = excluded.daily_checkin, health_profile_reminders = excluded.health_profile_reminders,
        connection_requests = excluded.connection_requests, connection_activity = excluded.connection_activity,
        reports_ready = excluded.reports_ready, subscription_payments = excluded.subscription_payments,
        updated_at = now();
END
$$;

COMMENT ON PROCEDURE notify.pr_set_notification_preferences (uuid, jsonb) IS
'Replace the caller''s 12 notification toggles (all keys required, unknown keys rejected)';
REVOKE ALL ON PROCEDURE notify.pr_set_notification_preferences(uuid, jsonb) FROM public;
GRANT EXECUTE ON PROCEDURE notify.pr_set_notification_preferences(uuid, jsonb) TO app_rw;

CREATE OR REPLACE FUNCTION notify.fn_reminders(p_user_id uuid)
RETURNS TABLE (
    reminder_type common.code,
    enabled boolean,
    times text[],
    interval_min smallint,
    saved boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    WITH suggested (type, times, interval_min, ord) AS (
        VALUES
            ('hydration', ARRAY[]::time[], 120::smallint, 1),
            ('nutrition', ARRAY['08:30', '13:00', '20:00']::time[], NULL::smallint, 2),
            ('sleep', ARRAY['22:00']::time[], NULL::smallint, 3),
            ('daily_checkin', ARRAY['09:00']::time[], NULL::smallint, 4),
            ('health_profile', ARRAY['10:00']::time[], NULL::smallint, 5)
    )
    SELECT
        s.type::common.code,
        coalesce(r.enabled, FALSE),
        ARRAY(
            SELECT to_char(t, 'HH24:MI') FROM unnest(CASE WHEN r.id IS NULL THEN s.times ELSE r.times END) AS t
            ORDER BY t
        ),
        CASE WHEN r.id IS NULL THEN s.interval_min ELSE r.interval_min END,
        r.id IS NOT NULL
    FROM suggested AS s
    LEFT JOIN notify.reminder AS r ON r.user_id = p_user_id AND r.type = s.type
    ORDER BY s.ord;
END
$$;

COMMENT ON FUNCTION notify.fn_reminders(uuid) IS
'The caller''s reminder schedules; unsaved types come back disabled with suggested times';
REVOKE ALL ON FUNCTION notify.fn_reminders(uuid) FROM public;
GRANT EXECUTE ON FUNCTION notify.fn_reminders(uuid) TO app_rw;

CREATE OR REPLACE PROCEDURE notify.pr_set_reminders(p_user_id uuid, p_reminders jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_item jsonb;
    v_key text;
    v_type text;
    v_times time[];
    v_interval smallint;
    v_seen text[] := ARRAY[]::text[];
    v_raw text;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_reminders IS NULL OR jsonb_typeof(p_reminders) <> 'array' OR jsonb_array_length(p_reminders) > 5 THEN
        RAISE EXCEPTION 'reminders must be a list of at most 5' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
    END IF;
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_reminders) LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RAISE EXCEPTION 'reminder must be an object' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
        END IF;
        FOR v_key IN SELECT jsonb_object_keys(v_item) LOOP
            IF v_key NOT IN ('type', 'enabled', 'times', 'interval_min') THEN
                RAISE EXCEPTION 'unknown reminder field' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
            END IF;
        END LOOP;
        v_type := v_item ->> 'type';
        IF v_type IS NULL OR v_type NOT IN ('hydration', 'nutrition', 'sleep', 'daily_checkin', 'health_profile')
           OR v_type = ANY (v_seen) THEN
            RAISE EXCEPTION 'unknown or repeated reminder type' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
        END IF;
        v_seen := v_seen || v_type;
        IF jsonb_typeof(v_item -> 'enabled') IS DISTINCT FROM 'boolean' THEN
            RAISE EXCEPTION 'enabled must be true or false' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
        END IF;

        v_times := ARRAY[]::time[];
        IF v_item ? 'times' AND jsonb_typeof(v_item -> 'times') <> 'null' THEN
            IF jsonb_typeof(v_item -> 'times') <> 'array' OR jsonb_array_length(v_item -> 'times') > 12 THEN
                RAISE EXCEPTION 'at most 12 times' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
            END IF;
            FOR v_raw IN SELECT value FROM jsonb_array_elements_text(v_item -> 'times') LOOP
                IF v_raw !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
                    RAISE EXCEPTION 'times must be HH:MM' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
                END IF;
                IF v_raw::time = ANY (v_times) THEN
                    RAISE EXCEPTION 'times must be distinct' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
                END IF;
                v_times := v_times || v_raw::time;
            END LOOP;
        END IF;

        v_interval := NULL;
        IF v_item ? 'interval_min' AND jsonb_typeof(v_item -> 'interval_min') <> 'null' THEN
            IF jsonb_typeof(v_item -> 'interval_min') <> 'number'
               OR (v_item ->> 'interval_min') !~ '^[0-9]{2,3}$'
               OR (v_item ->> 'interval_min')::integer NOT BETWEEN 60 AND 240 THEN
                RAISE EXCEPTION 'interval must be 60..240 minutes' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
            END IF;
            v_interval := (v_item ->> 'interval_min')::smallint;
        END IF;
        IF cardinality(v_times) > 0 AND v_interval IS NOT NULL THEN
            RAISE EXCEPTION 'times or an interval, not both' USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
        END IF;
        IF (v_item ->> 'enabled')::boolean AND cardinality(v_times) = 0 AND v_interval IS NULL THEN
            RAISE EXCEPTION 'an enabled reminder needs times or an interval'
                USING ERRCODE = '22023', DETAIL = 'REMINDERS_INVALID';
        END IF;

        INSERT INTO notify.reminder (user_id, type, enabled, times, interval_min)
        VALUES (
            p_user_id, v_type, (v_item ->> 'enabled')::boolean,
            ARRAY(SELECT t FROM unnest(v_times) AS t ORDER BY t), v_interval
        )
        ON CONFLICT ON CONSTRAINT uq_reminder__user_type DO UPDATE SET
            enabled = excluded.enabled, times = excluded.times, interval_min = excluded.interval_min,
            updated_at = now();
    END LOOP;
END
$$;

COMMENT ON PROCEDURE notify.pr_set_reminders (uuid, jsonb) IS
'Save the caller''s reminder schedules (per type: times HH:MM <= 12 or an interval 60-240 min)';
REVOKE ALL ON PROCEDURE notify.pr_set_reminders(uuid, jsonb) FROM public;
GRANT EXECUTE ON PROCEDURE notify.pr_set_reminders(uuid, jsonb) TO app_rw;
