-- PDF report requests for the API (Session 14, doc 04 section 2.11, OQ-38).
--   * pr_create_report_job: POST /reports. Idempotent by (user, Idempotency-Key): a replay returns the
--     first job (o_created false). Rules:
--       - monthly: any tier; from the month the account was created (V028) up to the current month;
--         the period ends today for the current month.
--       - custom: STAR (custom_report); from <= to <= today; at most 366 days.
--       - sleep: STAR now, or (monthly) a month with sleep data: sleep can only be logged on STAR, so
--         such a month was a STAR month and stays in its report after a downgrade (OQ-38).
--       - insights: STAR (report_insights) and the ai_processing consent (aggregates only go to the model).
--       - at least one active day in the period (REPORT_NO_DATA, 422).
--       - at most 10 requests per 24 hours (REPORT_LIMIT_REACHED, 429).
--   * fn_report_job / fn_report_jobs: GET /reports/{id} and GET /reports (last 12 months).
-- Errors: 42501 not found (404); P0001 UPGRADE_REQUIRED / CONSENT_REQUIRED / ONBOARDING_INCOMPLETE /
--         REPORT_LIMIT_REACHED / REPORT_NO_DATA; 22023 REPORT_RANGE_INVALID.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE report.pr_create_report_job(
    p_user_id uuid,
    p_idempotency_key uuid,
    p_kind text,
    p_from date,
    p_to date,
    p_sections text [],
    INOUT o_report_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL,
    INOUT o_created boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_today date;
    v_joined date;
    v_features jsonb;
    v_from date := p_from;
    v_to date := p_to;
    v_sections common.code [];
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT j.id, j.status INTO o_report_id, o_status
    FROM report.report_job AS j
    WHERE j.user_id = p_user_id AND j.idempotency_key = p_idempotency_key;
    IF FOUND THEN
        o_created := FALSE;
        RETURN;
    END IF;

    SELECT p.timezone INTO v_timezone
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    v_today := common.fn_local_date(v_timezone);
    SELECT (a.created_at AT TIME ZONE coalesce(v_timezone, 'Asia/Kolkata'))::date INTO v_joined
    FROM auth.user_account AS a WHERE a.id = p_user_id;
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;

    IF cardinality(p_sections) IS NULL OR cardinality(p_sections) > 4
       OR NOT p_sections <@ ARRAY['hydration', 'nutrition', 'sleep', 'insights']
       OR NOT p_sections && ARRAY['hydration', 'nutrition', 'sleep'] THEN
        RAISE EXCEPTION 'unknown sections' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    SELECT array_agg(DISTINCT s ORDER BY s)::common.code [] INTO v_sections FROM unnest(p_sections) AS s;

    IF p_kind = 'monthly' THEN
        v_from := date_trunc('month', p_from)::date;
        v_to := least((v_from + interval '1 month - 1 day')::date, v_today);
        IF v_from > v_today OR v_from < date '2026-01-01'
           OR v_from < date_trunc('month', v_joined)::date THEN
            RAISE EXCEPTION 'month out of range' USING ERRCODE = '22023', DETAIL = 'REPORT_RANGE_INVALID';
        END IF;
    ELSIF p_kind = 'custom' THEN
        IF NOT coalesce((v_features ->> 'custom_report')::boolean, FALSE) THEN
            RAISE EXCEPTION 'custom reports need STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
        END IF;
        IF v_from IS NULL OR v_to IS NULL OR v_from > v_to OR v_to > v_today
           OR v_to - v_from > 365 OR v_from < date '2026-01-01' THEN
            RAISE EXCEPTION 'bad range' USING ERRCODE = '22023', DETAIL = 'REPORT_RANGE_INVALID';
        END IF;
    ELSE
        RAISE EXCEPTION 'unknown kind' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;

    IF 'sleep' = ANY (v_sections)
       AND NOT coalesce((v_features ->> 'sleep')::boolean, FALSE)
       AND NOT (
           p_kind = 'monthly' AND EXISTS (
               SELECT 1 FROM sleep.daily_summary AS d
               WHERE d.user_id = p_user_id AND d.local_date BETWEEN v_from AND v_to
           )
       ) THEN
        RAISE EXCEPTION 'sleep needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;
    IF 'insights' = ANY (v_sections) THEN
        IF NOT coalesce((v_features ->> 'report_insights')::boolean, FALSE) THEN
            RAISE EXCEPTION 'insights need STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
        END IF;
        IF NOT coalesce((
            SELECT c.granted FROM privacy.consent_record AS c
            WHERE c.user_id = p_user_id AND c.purpose = 'ai_processing'
            ORDER BY c.recorded_at DESC, c.id DESC
            LIMIT 1
        ), FALSE) THEN
            RAISE EXCEPTION 'AI consent needed' USING ERRCODE = 'P0001', DETAIL = 'CONSENT_REQUIRED';
        END IF;
    END IF;

    -- Nothing logged in the period: no report to build (owner 2026-11-08).
    IF NOT EXISTS (
        SELECT 1 FROM app.user_activity_day AS d
        WHERE d.user_id = p_user_id AND d.local_date BETWEEN v_from AND v_to
          AND (d.has_hydration OR d.has_nutrition OR d.has_sleep)
    ) THEN
        RAISE EXCEPTION 'no data in this period' USING ERRCODE = 'P0001', DETAIL = 'REPORT_NO_DATA';
    END IF;

    IF (
        SELECT count(*) FROM report.report_job AS j
        WHERE j.user_id = p_user_id AND j.created_at > now() - interval '24 hours'
    ) >= 10 THEN
        RAISE EXCEPTION 'report limit' USING ERRCODE = 'P0001', DETAIL = 'REPORT_LIMIT_REACHED';
    END IF;

    INSERT INTO report.report_job (user_id, idempotency_key, kind, period_from, period_to, sections)
    VALUES (p_user_id, p_idempotency_key, p_kind, v_from, v_to, v_sections)
    ON CONFLICT (user_id, idempotency_key) DO NOTHING
    RETURNING id, status INTO o_report_id, o_status;
    o_created := FOUND;
    IF NOT o_created THEN
        SELECT j.id, j.status INTO o_report_id, o_status
        FROM report.report_job AS j
        WHERE j.user_id = p_user_id AND j.idempotency_key = p_idempotency_key;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION report.fn_report_jobs(
    p_user_id uuid, p_report_id uuid DEFAULT NULL, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 20
)
RETURNS TABLE (
    report_id uuid,
    kind common.code,
    period_from date,
    period_to date,
    sections common.code [],
    status common.code,
    storage_key common.object_key,
    size_bytes integer,
    error_code common.code,
    created_at timestamptz,
    expires_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT
        j.id, j.kind, j.period_from, j.period_to, j.sections,
        CASE WHEN j.status = 'ready' AND j.expires_at <= now() THEN 'expired'::common.code ELSE j.status END,
        CASE WHEN j.status = 'ready' AND j.expires_at > now() THEN j.storage_key END::common.object_key,
        j.size_bytes, j.error_code, j.created_at, j.expires_at
    FROM report.report_job AS j
    WHERE j.user_id = p_user_id
      AND (p_report_id IS NULL OR j.id = p_report_id)
      AND (p_before IS NULL OR j.created_at < p_before)
      AND j.created_at > now() - interval '12 months'
    ORDER BY j.created_at DESC
    LIMIT least(greatest(coalesce(p_limit, 20), 1), 50);
    IF p_report_id IS NOT NULL AND NOT FOUND THEN
        RAISE EXCEPTION 'report not found' USING ERRCODE = '42501';
    END IF;
END
$$;

COMMENT ON PROCEDURE report.pr_create_report_job(uuid, uuid, text, date, date, text [], uuid, text, boolean) IS
'POST /reports: queue a monthly or custom PDF report (idempotent; tier, consent and daily-limit rules)';
COMMENT ON FUNCTION report.fn_report_jobs(uuid, uuid, timestamptz, integer) IS
'GET /reports and GET /reports/{id}: the caller''s report jobs, newest first (last 12 months)';

REVOKE ALL ON PROCEDURE report.pr_create_report_job(uuid, uuid, text, date, date, text [], uuid, text, boolean) FROM public;
REVOKE ALL ON FUNCTION report.fn_report_jobs(uuid, uuid, timestamptz, integer) FROM public;
GRANT EXECUTE ON PROCEDURE report.pr_create_report_job(uuid, uuid, text, date, date, text [], uuid, text, boolean) TO app_rw;
GRANT EXECUTE ON FUNCTION report.fn_report_jobs(uuid, uuid, timestamptz, integer) TO app_rw;
