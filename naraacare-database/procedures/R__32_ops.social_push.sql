-- Social push fan-out for the worker (Session 12; doc 05 section 7 owner-run allow-list). Crosses
-- users, so it is owned by migration_owner (table owner: RLS does not apply) and granted only to
-- app_worker; no API login role can call it, and it takes no user input.
--   * ops.fn_social_pushes(p_after, p_until): in-app rows of the circles / connections categories
--     created in (p_after, p_until], one row per active device with a push token. Session 14 adds
--     the personal progress (streak milestones) and reports (report ready / failed) categories,
--     switched by streak_milestones and reports_ready. Per-circle
--     switches were applied when the row was written; here the global toggles apply
--     (goal_completions for circle goals, connection_requests for requests, connection_activity for
--     the rest) and quiet hours (default 22:30-07:00 local) skip the push, never the in-app row.
-- The push text is a fixed template (no message text, no health values, OQ-41). The worker keeps
-- its own cursor and deduplicates per notification and device (at-least-once queue).
CREATE OR REPLACE FUNCTION ops.fn_social_pushes(
    p_after timestamptz,
    p_until timestamptz,
    p_limit integer DEFAULT 2000,
    p_quiet_start time DEFAULT '22:30',
    p_quiet_end time DEFAULT '07:00'
)
RETURNS TABLE (
    notification_id uuid,
    created_at timestamptz,
    user_id uuid,
    template_code text,
    deep_link text,
    device_id uuid,
    push_token text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT n.id, n.created_at, n.user_id, n.template_code::text, n.deep_link::text, dv.id, dv.push_token::text
    FROM notify.notification AS n
    INNER JOIN auth.user_account AS a ON a.id = n.user_id AND a.status = 'active'
    INNER JOIN app.user_profile AS p ON p.user_id = n.user_id AND p.deleted_at IS NULL
    LEFT JOIN notify.notification_preference AS np ON np.user_id = n.user_id
    INNER JOIN notify.device AS dv
        ON dv.user_id = n.user_id AND dv.revoked_at IS NULL AND dv.push_token IS NOT NULL
    WHERE n.created_at > p_after AND n.created_at <= p_until
      AND n.category IN ('circles', 'connections', 'progress', 'reports')
      AND CASE
              WHEN n.template_code = 'circle_goal_completed' THEN coalesce(np.goal_completions, TRUE)
              WHEN n.template_code = 'streak_milestone' THEN coalesce(np.streak_milestones, TRUE)
              WHEN n.category = 'reports' THEN coalesce(np.reports_ready, TRUE)
              WHEN n.template_code = 'connection_request' THEN coalesce(np.connection_requests, TRUE)
              ELSE coalesce(np.connection_activity, TRUE)
          END
      AND NOT ops.fn_is_quiet((n.created_at AT TIME ZONE p.timezone)::time, p_quiet_start, p_quiet_end)
    ORDER BY n.created_at, n.id, dv.id
    LIMIT least(greatest(coalesce(p_limit, 2000), 1), 5000);
$$;

COMMENT ON FUNCTION ops.fn_social_pushes(timestamptz, timestamptz, integer, time, time) IS
'Worker: devices to push for social notifications in a time window (global toggles, quiet hours)';
REVOKE ALL ON FUNCTION ops.fn_social_pushes(timestamptz, timestamptz, integer, time, time) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_social_pushes(timestamptz, timestamptz, integer, time, time) TO app_worker;
