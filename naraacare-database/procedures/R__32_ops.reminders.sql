-- Reminder fan-out for the push worker (Session 09; doc 05 section 7 owner-run allow-list). These
-- cross users, so they are owned by migration_owner (table owner: RLS does not apply) and granted only
-- to app_worker; no API login role can call them, and they take no user input.
--   * ops.fn_due_reminders(p_now): reminders due in the minute of p_now, in each user's local time:
--     a saved, enabled schedule whose times contain that minute, or whose interval divides the
--     minutes since wake time (strictly between wake and bedtime). The matching preference toggle
--     must be on, the minute must be outside quiet hours (default 22:30-07:00 local), and hydration
--     reminders stop once today's goal is completed.
--   * ops.fn_day_ending_soon(p_now): users whose bedtime is p_hours (doc 06 section 3.8: 3 h) away,
--     within the p_window_min slot of the 15-minute job, with the hydration reminder enabled and
--     today's goal not completed yet.
--   * ops.pr_revoke_push_token(p_device_id): FCM said the token is no longer registered.
-- Both functions return one row per active device with a push token. Push texts are generic, never health values (OQ-41); the worker deduplicates
-- per user, type and minute, because the queue delivers at least once.
CREATE OR REPLACE FUNCTION ops.fn_is_quiet(p_local time, p_quiet_start time, p_quiet_end time)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT CASE
        WHEN p_quiet_start IS NULL OR p_quiet_end IS NULL OR p_quiet_start = p_quiet_end THEN FALSE
        WHEN p_quiet_start > p_quiet_end THEN p_local >= p_quiet_start OR p_local < p_quiet_end
        ELSE p_local >= p_quiet_start AND p_local < p_quiet_end
    END
$$;

COMMENT ON FUNCTION ops.fn_is_quiet(time, time, time) IS 'TRUE when a local time falls in the quiet hours (wraps midnight)';
REVOKE ALL ON FUNCTION ops.fn_is_quiet(time, time, time) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_is_quiet(time, time, time) TO app_worker;

CREATE OR REPLACE FUNCTION ops.fn_due_reminders(
    p_now timestamptz,
    p_quiet_start time DEFAULT '22:30',
    p_quiet_end time DEFAULT '07:00'
)
RETURNS TABLE (
    user_id uuid,
    reminder_type text,
    device_id uuid,
    platform text,
    push_token text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    WITH due AS (
        SELECT
            r.user_id, r.type::text AS reminder_type, r.times, r.interval_min,
            date_trunc('minute', p_now AT TIME ZONE p.timezone) AS local_ts,
            p.wake_local, p.sleep_start_local, p.timezone
        FROM notify.reminder AS r
        INNER JOIN app.user_profile AS p ON p.user_id = r.user_id AND p.deleted_at IS NULL
        INNER JOIN auth.user_account AS a ON a.id = r.user_id AND a.status = 'active'
        WHERE r.enabled
    ),
    matched AS (
        SELECT d.*
        FROM due AS d
        CROSS JOIN LATERAL (
            SELECT
                (extract(epoch FROM (d.local_ts::time - d.wake_local))::integer / 60 + 1440) % 1440 AS since_wake,
                (extract(epoch FROM (d.sleep_start_local - d.wake_local))::integer / 60 + 1440) % 1440 AS awake_min
        ) AS m
        WHERE
            (
                d.local_ts::time = ANY (d.times)
                OR (
                    d.interval_min IS NOT NULL AND m.since_wake > 0 AND m.since_wake < m.awake_min
                    AND m.since_wake % d.interval_min = 0
                )
            )
            AND NOT ops.fn_is_quiet(d.local_ts::time, p_quiet_start, p_quiet_end)
    )
    SELECT m.user_id, m.reminder_type, dv.id, dv.platform::text, dv.push_token::text
    FROM matched AS m
    LEFT JOIN notify.notification_preference AS np ON np.user_id = m.user_id
    INNER JOIN notify.device AS dv
        ON dv.user_id = m.user_id AND dv.revoked_at IS NULL AND dv.push_token IS NOT NULL
    WHERE
        CASE m.reminder_type
            WHEN 'hydration' THEN coalesce(np.hydration_reminders, TRUE)
            WHEN 'nutrition' THEN coalesce(np.nutrition_reminders, TRUE)
            WHEN 'sleep' THEN coalesce(np.sleep_reminders, TRUE)
            WHEN 'daily_checkin' THEN coalesce(np.daily_checkin, FALSE)
            WHEN 'health_profile' THEN coalesce(np.health_profile_reminders, TRUE)
            ELSE FALSE
        END
        AND NOT (
            m.reminder_type = 'hydration' AND EXISTS (
                SELECT 1 FROM hydration.daily_summary AS hs
                WHERE hs.user_id = m.user_id AND hs.local_date = m.local_ts::date
                    AND hs.goal_completed_at IS NOT NULL
            )
        )
    ORDER BY m.user_id, m.reminder_type, dv.id;
$$;

COMMENT ON FUNCTION ops.fn_due_reminders(timestamptz, time, time) IS
'Worker: devices to notify for reminders due in the minute of p_now (local times, prefs, quiet hours)';
REVOKE ALL ON FUNCTION ops.fn_due_reminders(timestamptz, time, time) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_due_reminders(timestamptz, time, time) TO app_worker;

CREATE OR REPLACE FUNCTION ops.fn_day_ending_soon(
    p_now timestamptz,
    p_hours numeric DEFAULT 3,
    p_window_min integer DEFAULT 15,
    p_quiet_start time DEFAULT '22:30',
    p_quiet_end time DEFAULT '07:00'
)
RETURNS TABLE (
    user_id uuid,
    device_id uuid,
    platform text,
    push_token text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    WITH candidates AS (
        SELECT
            p.user_id,
            date_trunc('minute', p_now AT TIME ZONE p.timezone) AS local_ts,
            p.sleep_start_local
        FROM notify.reminder AS r
        INNER JOIN app.user_profile AS p ON p.user_id = r.user_id AND p.deleted_at IS NULL
        INNER JOIN auth.user_account AS a ON a.id = r.user_id AND a.status = 'active'
        LEFT JOIN notify.notification_preference AS np ON np.user_id = r.user_id
        WHERE r.type = 'hydration' AND r.enabled AND coalesce(np.hydration_reminders, TRUE)
    )
    SELECT c.user_id, dv.id, dv.platform::text, dv.push_token::text
    FROM candidates AS c
    CROSS JOIN LATERAL (
        SELECT (extract(epoch FROM (c.sleep_start_local - c.local_ts::time))::integer / 60 + 1440) % 1440 AS to_bed
    ) AS m
    INNER JOIN notify.device AS dv
        ON dv.user_id = c.user_id AND dv.revoked_at IS NULL AND dv.push_token IS NOT NULL
    WHERE
        m.to_bed <= p_hours * 60 AND m.to_bed > p_hours * 60 - p_window_min
        AND NOT ops.fn_is_quiet(c.local_ts::time, p_quiet_start, p_quiet_end)
        AND NOT EXISTS (
            SELECT 1 FROM hydration.daily_summary AS hs
            WHERE hs.user_id = c.user_id AND hs.local_date = c.local_ts::date AND hs.goal_completed_at IS NOT NULL
        )
    ORDER BY c.user_id, dv.id;
$$;

COMMENT ON FUNCTION ops.fn_day_ending_soon(timestamptz, numeric, integer, time, time) IS
'Worker: devices to nudge when bedtime is p_hours away and today''s hydration goal is not met';
REVOKE ALL ON FUNCTION ops.fn_day_ending_soon(timestamptz, numeric, integer, time, time) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_day_ending_soon(timestamptz, numeric, integer, time, time) TO app_worker;

CREATE OR REPLACE PROCEDURE ops.pr_revoke_push_token(p_device_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    UPDATE notify.device AS d
    SET push_token = NULL, updated_at = now()
    WHERE d.id = p_device_id AND d.push_token IS NOT NULL;
END
$$;

COMMENT ON PROCEDURE ops.pr_revoke_push_token (uuid) IS 'Worker: wipe a push token FCM reported as unregistered';
REVOKE ALL ON PROCEDURE ops.pr_revoke_push_token(uuid) FROM public;
GRANT EXECUTE ON PROCEDURE ops.pr_revoke_push_token(uuid) TO app_worker;
