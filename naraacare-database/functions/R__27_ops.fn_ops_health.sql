-- Owner alerts (2026-11-17): one cross-user read for the worker's health check (every 5 minutes),
-- which emails ERROR_ALERT_EMAIL when a number crosses its limit. Counts and a sum only: no ids, no
-- user data. Lives in ops: owned by migration_owner (table owner: RLS does not apply) and granted
-- only to app_worker (doc 05 section 7).
--   * reports_stuck: report jobs queued for over 15 minutes or running for over 10 minutes.
--   * reports_failed_1h: report jobs that ended in failed during the last hour.
--   * store_notifications_failed_1h: Play / App Store notifications whose processing failed.
--   * paid_without_star: store subscriptions that should give access now (same rule as
--     billing.fn_entitlement_of) while the user's effective tier is still standard.
--   * ai_spend_month_micro_inr: our AI spend this calendar month (UTC, as OpenAI bills), real model
--     calls only. Basic-mode Rin replies (model 'rin-basic') are metered for the user's limit but
--     cost us nothing, so they are left out.

CREATE OR REPLACE FUNCTION ops.fn_ops_health()
RETURNS TABLE (
    reports_stuck integer,
    reports_failed_1h integer,
    store_notifications_failed_1h integer,
    paid_without_star integer,
    ai_spend_month_micro_inr bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        (
            SELECT count(*)
            FROM report.report_job AS j
            WHERE (j.status = 'queued' AND j.created_at < now() - interval '15 minutes')
               OR (j.status = 'running' AND j.started_at < now() - interval '10 minutes')
        )::integer,
        (
            SELECT count(*)
            FROM report.report_job AS j
            WHERE j.status = 'failed' AND j.finished_at >= now() - interval '1 hour'
        )::integer,
        (
            SELECT count(*)
            FROM billing.store_notification AS n
            WHERE n.status = 'failed' AND n.received_at >= now() - interval '1 hour'
        )::integer,
        (
            SELECT count(*)
            FROM billing.subscription AS s
            CROSS JOIN LATERAL billing.fn_entitlement_of(s.user_id) AS e
            WHERE s.deleted_at IS NULL
              AND (
                  (s.status IN ('active', 'canceled') AND s.current_period_end > now())
                  OR s.status = 'in_grace'
              )
              AND e.tier_code = 'standard'
        )::integer,
        (
            SELECT coalesce(sum(u.cost_micro_inr), 0)
            FROM ai.usage_event AS u
            WHERE u.created_at >= date_trunc('month', now() AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
              AND u.model <> 'rin-basic'
        )::bigint;
$$;

COMMENT ON FUNCTION ops.fn_ops_health() IS
'Worker health check for owner alerts: stuck/failed reports, failed store notifications, paid-without-STAR count, AI spend this month (counts only)';

REVOKE ALL ON FUNCTION ops.fn_ops_health() FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_ops_health() TO app_worker;
