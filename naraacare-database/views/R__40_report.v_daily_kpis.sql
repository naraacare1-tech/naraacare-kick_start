-- Aggregated daily KPIs for the BI login `reporting` (Session 14, doc 05 section 7). Counts only: no
-- user ids, no health values, no text. The view runs as its owner (migration_owner), so `reporting`
-- needs no access to the base tables. Days with fewer than 5 active users show NULL user counts so a
-- small day cannot single anyone out.
CREATE OR REPLACE VIEW report.v_daily_kpis AS
WITH days AS (
    SELECT d.local_date, count(*) AS active_users,
           count(*) FILTER (WHERE d.has_hydration) AS hydration_users,
           count(*) FILTER (WHERE d.has_nutrition) AS nutrition_users,
           count(*) FILTER (WHERE d.has_sleep) AS sleep_users
    FROM app.user_activity_day AS d
    WHERE d.local_date >= current_date - 400
    GROUP BY d.local_date
),
signups AS (
    SELECT a.created_at::date AS local_date, count(*) AS new_accounts
    FROM auth.user_account AS a
    WHERE a.created_at >= current_date - 400
    GROUP BY 1
),
reports AS (
    SELECT j.created_at::date AS local_date, count(*) AS reports_requested,
           count(*) FILTER (WHERE j.status IN ('ready', 'expired')) AS reports_ready
    FROM report.report_job AS j
    WHERE j.created_at >= current_date - 400
    GROUP BY 1
),
tickets AS (
    SELECT t.created_at::date AS local_date, count(*) AS support_tickets
    FROM support.ticket AS t
    WHERE t.created_at >= current_date - 400
    GROUP BY 1
)
SELECT
    coalesce(d.local_date, s.local_date, r.local_date, t.local_date) AS day,
    CASE WHEN d.active_users >= 5 THEN d.active_users END AS active_users,
    CASE WHEN d.active_users >= 5 THEN d.hydration_users END AS hydration_users,
    CASE WHEN d.active_users >= 5 THEN d.nutrition_users END AS nutrition_users,
    CASE WHEN d.active_users >= 5 THEN d.sleep_users END AS sleep_users,
    coalesce(s.new_accounts, 0) AS new_accounts,
    coalesce(r.reports_requested, 0) AS reports_requested,
    coalesce(r.reports_ready, 0) AS reports_ready,
    coalesce(t.support_tickets, 0) AS support_tickets
FROM days AS d
FULL JOIN signups AS s ON s.local_date = d.local_date
FULL JOIN reports AS r ON r.local_date = coalesce(d.local_date, s.local_date)
FULL JOIN tickets AS t ON t.local_date = coalesce(d.local_date, s.local_date, r.local_date);

COMMENT ON VIEW report.v_daily_kpis IS 'BI: daily active users, sign-ups, reports and tickets (counts only)';
REVOKE ALL ON report.v_daily_kpis FROM public;
GRANT SELECT ON report.v_daily_kpis TO reporting;
