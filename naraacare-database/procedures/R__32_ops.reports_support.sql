-- Report and support workers (Session 14). Cross-user routines, so they live in ops: owned by
-- migration_owner (table owner: RLS does not apply) and granted only to app_worker (doc 05 section 7).
-- They take no user text; the worker passes only ids, codes, counts and storage keys it generated.

--   * fn_claim_report_jobs: takes queued jobs (and jobs stuck in running for 10 minutes) with
--     SKIP LOCKED, marks them running, and returns what the builder needs: the period, sections, the
--     user's name / username / timezone, and whether AI insights are still allowed now (STAR +
--     ai_processing consent) with this month's AI spend for the monthly cap (V026).
--   * fn_report_days: daily aggregates for the job's period, only for the requested sections (no
--     entries, no free text). These aggregates are the only data the insights model sees.
--   * fn_report_extras: numbers for the report pages (previous-period averages, meal shares, counts,
--     macro targets, sleep thresholds).
--   * pr_record_insight_usage: the insight call's tokens and cost count against the monthly AI cap.
--   * pr_finish_report_job: ready (file kept 7 days) + "report ready" notification, or a retry
--     (up to 3 attempts) and then failed + "report failed" notification.
--   * fn_expire_reports: ready jobs past expiry -> expired; returns the storage keys to delete.

CREATE OR REPLACE FUNCTION ops.fn_claim_report_jobs(p_limit integer DEFAULT 5)
RETURNS TABLE (
    report_id uuid,
    user_id uuid,
    kind text,
    period_from date,
    period_to date,
    sections text [],
    attempts smallint,
    full_name text,
    username text,
    timezone text,
    insights_allowed boolean,
    ai_spend_month_micro_inr bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH picked AS (
        SELECT j.id
        FROM report.report_job AS j
        WHERE j.status = 'queued'
           OR (j.status = 'running' AND j.started_at < now() - interval '10 minutes')
        ORDER BY j.created_at
        LIMIT least(greatest(coalesce(p_limit, 5), 1), 20)
        FOR UPDATE SKIP LOCKED
    ),
    claimed AS (
        UPDATE report.report_job AS j
        SET status = 'running', started_at = now(), attempts = j.attempts + 1
        FROM picked
        WHERE j.id = picked.id
        RETURNING j.id, j.user_id, j.kind, j.period_from, j.period_to, j.sections, j.attempts
    )
    SELECT
        c.id, c.user_id, c.kind::text, c.period_from, c.period_to, c.sections::text [], c.attempts,
        p.full_name::text, p.username::text, coalesce(p.timezone, 'Asia/Kolkata')::text,
        coalesce((e.features ->> 'report_insights')::boolean, FALSE) AND coalesce((
            SELECT r.granted FROM privacy.consent_record AS r
            WHERE r.user_id = c.user_id AND r.purpose = 'ai_processing'
            ORDER BY r.recorded_at DESC, r.id DESC
            LIMIT 1
        ), FALSE),
        coalesce((
            SELECT sum(u.cost_micro_inr)
            FROM ai.usage_event AS u
            WHERE u.user_id = c.user_id
              AND u.local_date >= date_trunc(
                  'month', common.fn_local_date(coalesce(p.timezone, 'Asia/Kolkata'))
              )::date
        ), 0)::bigint
    FROM claimed AS c
    LEFT JOIN app.user_profile AS p ON p.user_id = c.user_id
    LEFT JOIN LATERAL billing.fn_entitlement_of(c.user_id) AS e ON TRUE;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_report_days(p_report_id uuid)
RETURNS TABLE (
    local_date date,
    water_ml integer,
    effective_ml numeric,
    need_ml integer,
    hydration_goal_met boolean,
    kcal numeric,
    allowance_kcal integer,
    protein_g numeric,
    carbs_g numeric,
    fat_g numeric,
    fiber_g numeric,
    sugar_g numeric,
    sodium_mg numeric,
    meal_count smallint,
    sleep_min smallint,
    sleep_goal_min smallint,
    sleep_score_pct smallint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    WITH j AS (
        SELECT r.user_id, r.period_from, r.period_to,
               'hydration' = ANY (r.sections) AS h, 'nutrition' = ANY (r.sections) AS n,
               'sleep' = ANY (r.sections) AS s
        FROM report.report_job AS r WHERE r.id = p_report_id
    )
    SELECT
        g.day::date,
        CASE WHEN j.h THEN hd.volume_ml END,
        CASE WHEN j.h THEN hd.effective_intake_ml END,
        CASE WHEN j.h THEN hd.daily_need_ml END,
        CASE WHEN j.h THEN hd.goal_completed_at IS NOT NULL END,
        CASE WHEN j.n THEN round(nd.calories_kcal_total, 0) END,
        CASE WHEN j.n THEN nd.effective_allowance_kcal END,
        CASE WHEN j.n THEN round(nd.protein_g_total, 1) END,
        CASE WHEN j.n THEN round(nd.carbohydrates_g_total, 1) END,
        CASE WHEN j.n THEN round(nd.fat_g_total, 1) END,
        CASE WHEN j.n THEN round(nd.dietary_fiber_g_total, 1) END,
        CASE WHEN j.n THEN round(nd.total_sugar_g_total, 1) END,
        CASE WHEN j.n THEN round(nd.sodium_mg_total, 0) END,
        CASE WHEN j.n THEN nd.meal_count END,
        CASE WHEN j.s THEN sd.counted_min END,
        CASE WHEN j.s THEN sd.goal_min END,
        CASE WHEN j.s THEN sd.score_pct END
    FROM j
    CROSS JOIN LATERAL generate_series(j.period_from, j.period_to, interval '1 day') AS g (day)
    LEFT JOIN hydration.daily_summary AS hd ON hd.user_id = j.user_id AND hd.local_date = g.day::date
    LEFT JOIN nutrition.daily_summary AS nd ON nd.user_id = j.user_id AND nd.local_date = g.day::date
    LEFT JOIN sleep.daily_summary AS sd ON sd.user_id = j.user_id AND sd.local_date = g.day::date
    ORDER BY 1;
$$;

CREATE OR REPLACE PROCEDURE ops.pr_record_insight_usage(
    p_report_id uuid,
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
BEGIN
    INSERT INTO ai.usage_event (
        user_id, local_date, feature, model, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens,
        cost_micro_inr
    )
    SELECT
        j.user_id, common.fn_local_date(coalesce(p.timezone, 'Asia/Kolkata')), 'report_insight', p_model,
        greatest(p_input_tokens, 0), greatest(p_output_tokens, 0),
        greatest(coalesce(p_cache_write_tokens, 0), 0), greatest(coalesce(p_cache_read_tokens, 0), 0),
        greatest(coalesce(p_cost_micro_inr, 0), 0)
    FROM report.report_job AS j
    LEFT JOIN app.user_profile AS p ON p.user_id = j.user_id
    WHERE j.id = p_report_id;
END
$$;

CREATE OR REPLACE PROCEDURE ops.pr_finish_report_job(
    p_report_id uuid,
    p_ok boolean,
    p_storage_key text DEFAULT NULL,
    p_size_bytes integer DEFAULT NULL,
    p_error_code text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_job report.report_job;
BEGIN
    SELECT * INTO v_job FROM report.report_job AS j WHERE j.id = p_report_id AND j.status = 'running' FOR UPDATE;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    IF p_ok THEN
        UPDATE report.report_job SET
            status = 'ready', storage_key = p_storage_key, size_bytes = p_size_bytes,
            finished_at = now(), expires_at = now() + interval '7 days', error_code = NULL
        WHERE id = p_report_id;
        INSERT INTO notify.notification (user_id, category, template_code, params, deep_link)
        VALUES (
            v_job.user_id, 'reports', 'report_ready',
            jsonb_build_object('report_id', v_job.id, 'from', v_job.period_from, 'to', v_job.period_to),
            'naraacare://profile/reports/' || v_job.id
        );
    ELSIF v_job.attempts < 3 THEN
        UPDATE report.report_job SET status = 'queued', error_code = p_error_code WHERE id = p_report_id;
    ELSE
        UPDATE report.report_job SET status = 'failed', error_code = p_error_code, finished_at = now()
        WHERE id = p_report_id;
        INSERT INTO notify.notification (user_id, category, template_code, params, deep_link)
        VALUES (
            v_job.user_id, 'reports', 'report_failed', jsonb_build_object('report_id', v_job.id),
            'naraacare://profile/reports'
        );
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_expire_reports(p_limit integer DEFAULT 500)
RETURNS TABLE (report_id uuid, storage_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH due AS (
        SELECT j.id FROM report.report_job AS j
        WHERE j.status = 'ready' AND j.expires_at <= now()
        ORDER BY j.expires_at
        LIMIT least(greatest(coalesce(p_limit, 500), 1), 5000)
        FOR UPDATE SKIP LOCKED
    )
    UPDATE report.report_job AS j SET status = 'expired'
    FROM due
    WHERE j.id = due.id
    RETURNING j.id, j.storage_key::text;
END
$$;

-- Extra figures for the report pages (owner 2026-11-08, Figma report): numbers only, requested
-- sections only. prev_* = averages over logged days of the same-length period just before (the
-- "vs previous N days" trends); meal_kcal_pct = share of calories per meal type; foods_logged /
-- meals_logged = counts; macro targets = average base calorie target x the nutr.macro.* shares of
-- the calc_version in force; sleep label thresholds for the good / fair / low split.
CREATE OR REPLACE FUNCTION ops.fn_report_extras(p_report_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    WITH j AS (
        SELECT r.user_id, r.period_from, r.period_to,
               (r.period_to - r.period_from + 1) AS n,
               'hydration' = ANY (r.sections) AS h, 'nutrition' = ANY (r.sections) AS nu,
               'sleep' = ANY (r.sections) AS s
        FROM report.report_job AS r WHERE r.id = p_report_id
    ),
    k AS (
        SELECT c.key, c.value FROM ref.calc_constant AS c
        WHERE c.calc_version = (
            SELECT max(cv.code) FROM ref.calc_version AS cv WHERE cv.effective_from <= current_date
        )
    ),
    prev AS (
        SELECT
            (SELECT round(avg(hd.volume_ml)) FROM hydration.daily_summary AS hd
             WHERE j.h AND hd.user_id = j.user_id AND hd.volume_ml > 0
               AND hd.local_date BETWEEN j.period_from - j.n AND j.period_from - 1) AS water_ml,
            (SELECT round(avg(nd.calories_kcal_total)) FROM nutrition.daily_summary AS nd
             WHERE j.nu AND nd.user_id = j.user_id AND nd.calories_kcal_total > 0
               AND nd.local_date BETWEEN j.period_from - j.n AND j.period_from - 1) AS kcal,
            (SELECT round(avg(nd.protein_g_total), 1) FROM nutrition.daily_summary AS nd
             WHERE j.nu AND nd.user_id = j.user_id AND nd.calories_kcal_total > 0
               AND nd.local_date BETWEEN j.period_from - j.n AND j.period_from - 1) AS protein_g,
            (SELECT round(avg(sd.counted_min)) FROM sleep.daily_summary AS sd
             WHERE j.s AND sd.user_id = j.user_id AND sd.counted_min > 0
               AND sd.local_date BETWEEN j.period_from - j.n AND j.period_from - 1) AS sleep_min
        FROM j
    ),
    meals AS (
        SELECT m.meal_type, sum(i.calories_kcal) AS kcal, count(*) AS items, count(DISTINCT m.id) AS meals
        FROM j
        INNER JOIN nutrition.meal AS m
            ON j.nu AND m.user_id = j.user_id AND m.deleted_at IS NULL
           AND m.local_date BETWEEN j.period_from AND j.period_to
        INNER JOIN nutrition.meal_item AS i
            ON i.meal_id = m.id AND i.meal_logged_at = m.logged_at AND i.deleted_at IS NULL
        GROUP BY m.meal_type
    ),
    base AS (
        SELECT avg(nd.base_target_kcal) AS kcal FROM j
        INNER JOIN nutrition.daily_summary AS nd
            ON j.nu AND nd.user_id = j.user_id AND nd.local_date BETWEEN j.period_from AND j.period_to
    )
    SELECT jsonb_strip_nulls(jsonb_build_object(
        'prev_days', j.n,
        'prev_water_ml', prev.water_ml,
        'prev_kcal', prev.kcal,
        'prev_protein_g', prev.protein_g,
        'prev_sleep_min', prev.sleep_min,
        'meal_kcal_pct', CASE WHEN j.nu THEN (
            SELECT jsonb_object_agg(meals.meal_type,
                round(100 * meals.kcal / nullif((SELECT sum(x.kcal) FROM meals AS x), 0)))
            FROM meals) END,
        'foods_logged', CASE WHEN j.nu THEN (SELECT coalesce(sum(items), 0) FROM meals) END,
        'meals_logged', CASE WHEN j.nu THEN (SELECT coalesce(sum(meals.meals), 0) FROM meals) END,
        'target_protein_g', CASE WHEN j.nu THEN round((SELECT kcal FROM base)
            * (SELECT value FROM k WHERE key = 'nutr.macro.protein_share')
            / (SELECT value FROM k WHERE key = 'nutr.macro.protein_kcal_per_g')) END,
        'target_carbs_g', CASE WHEN j.nu THEN round((SELECT kcal FROM base)
            * (SELECT value FROM k WHERE key = 'nutr.macro.carbs_share')
            / (SELECT value FROM k WHERE key = 'nutr.macro.carbs_kcal_per_g')) END,
        'target_fat_g', CASE WHEN j.nu THEN round((SELECT kcal FROM base)
            * (SELECT value FROM k WHERE key = 'nutr.macro.fat_share')
            / (SELECT value FROM k WHERE key = 'nutr.macro.fat_kcal_per_g')) END,
        'sleep_good_from_pct', CASE WHEN j.s THEN (SELECT value FROM k WHERE key = 'sleep.label.good_from_pct') END,
        'sleep_fair_from_pct', CASE WHEN j.s THEN (SELECT value FROM k WHERE key = 'sleep.label.fair_from_pct') END
    ))
    FROM j CROSS JOIN prev;
$$;

COMMENT ON FUNCTION ops.fn_claim_report_jobs(integer) IS
'Worker: claim queued report jobs (SKIP LOCKED) with the user context the PDF builder needs';
COMMENT ON FUNCTION ops.fn_report_days(uuid) IS
'Worker: daily aggregates of a report job''s period, for the requested sections only';
COMMENT ON FUNCTION ops.fn_report_extras(uuid) IS
'Worker: report page extras (previous-period averages, meal shares, counts, macro targets, sleep thresholds)';
COMMENT ON PROCEDURE ops.pr_record_insight_usage(uuid, text, integer, integer, integer, integer, bigint) IS
'Worker: record the AI insight call''s tokens against the user''s daily allowance';
COMMENT ON PROCEDURE ops.pr_finish_report_job(uuid, boolean, text, integer, text) IS
'Worker: mark a report ready (7 days) or retry / fail it, with an in-app notification';
COMMENT ON FUNCTION ops.fn_expire_reports(integer) IS
'Worker: expire ready reports after 7 days; returns the storage keys to delete';

REVOKE ALL ON FUNCTION ops.fn_claim_report_jobs(integer) FROM public;
REVOKE ALL ON FUNCTION ops.fn_report_days(uuid) FROM public;
REVOKE ALL ON FUNCTION ops.fn_report_extras(uuid) FROM public;
REVOKE ALL ON PROCEDURE ops.pr_record_insight_usage(uuid, text, integer, integer, integer, integer, bigint) FROM public;
REVOKE ALL ON PROCEDURE ops.pr_finish_report_job(uuid, boolean, text, integer, text) FROM public;
REVOKE ALL ON FUNCTION ops.fn_expire_reports(integer) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_claim_report_jobs(integer) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_report_days(uuid) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_report_extras(uuid) TO app_worker;
GRANT EXECUTE ON PROCEDURE ops.pr_record_insight_usage(uuid, text, integer, integer, integer, integer, bigint) TO app_worker;
GRANT EXECUTE ON PROCEDURE ops.pr_finish_report_job(uuid, boolean, text, integer, text) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_expire_reports(integer) TO app_worker;

-- Support forwarding (doc 04 section 2.13, OQ-51).
--   * fn_support_unforwarded: tickets and requests not yet emailed to the support inbox, with the
--     account email so support can reply; the email template escapes every value.
--   * pr_mark_support_forwarded: forwarded, or one more failed attempt (gives up after 20).

CREATE OR REPLACE FUNCTION ops.fn_support_unforwarded(p_limit integer DEFAULT 50)
RETURNS TABLE (
    kind text,
    item_id uuid,
    created_at timestamptz,
    ticket_ref text,
    category text,
    title text,
    body text,
    screenshot_key text,
    user_id uuid,
    username text,
    reply_email text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT * FROM (
        SELECT 'ticket', t.id, t.created_at, t.ticket_ref::text, t.category::text, NULL::text,
               t.description::text, t.screenshot_key::text, t.user_id, p.username::text, a.email::text
        FROM support.ticket AS t
        INNER JOIN auth.user_account AS a ON a.id = t.user_id
        LEFT JOIN app.user_profile AS p ON p.user_id = t.user_id
        WHERE t.forwarded_at IS NULL AND t.forward_attempts < 20
        UNION ALL
        SELECT 'feature_request', f.id, f.created_at, NULL, NULL, f.title::text,
               f.benefit::text, NULL, f.user_id, p.username::text, a.email::text
        FROM support.feature_request AS f
        INNER JOIN auth.user_account AS a ON a.id = f.user_id
        LEFT JOIN app.user_profile AS p ON p.user_id = f.user_id
        WHERE f.forwarded_at IS NULL AND f.forward_attempts < 20
    ) AS q
    ORDER BY q.created_at
    LIMIT least(greatest(coalesce(p_limit, 50), 1), 200);
$$;

CREATE OR REPLACE PROCEDURE ops.pr_mark_support_forwarded(p_kind text, p_item_id uuid, p_ok boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF p_kind = 'ticket' THEN
        UPDATE support.ticket SET
            forwarded_at = CASE WHEN p_ok THEN now() END,
            forward_attempts = least(forward_attempts + 1, 20)
        WHERE id = p_item_id AND forwarded_at IS NULL;
    ELSIF p_kind = 'feature_request' THEN
        UPDATE support.feature_request SET
            forwarded_at = CASE WHEN p_ok THEN now() END,
            forward_attempts = least(forward_attempts + 1, 20)
        WHERE id = p_item_id AND forwarded_at IS NULL;
    END IF;
END
$$;

COMMENT ON FUNCTION ops.fn_support_unforwarded(integer) IS
'Worker: tickets and feature requests still to be emailed to the support inbox';
COMMENT ON PROCEDURE ops.pr_mark_support_forwarded(text, uuid, boolean) IS
'Worker: record a forwarding attempt (success sets forwarded_at)';
REVOKE ALL ON FUNCTION ops.fn_support_unforwarded(integer) FROM public;
REVOKE ALL ON PROCEDURE ops.pr_mark_support_forwarded(text, uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_support_unforwarded(integer) TO app_worker;
GRANT EXECUTE ON PROCEDURE ops.pr_mark_support_forwarded(text, uuid, boolean) TO app_worker;
