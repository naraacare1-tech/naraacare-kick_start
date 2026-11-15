-- GET /sleep/summary?date= (doc 04 section 2.6). STAR only. The day's counted total, goal, score and
-- label (doc 06 section 4) with its entries in wake order, each with its night wakings, the edit flag
-- (last 2 within 7 days) and the version for If-Match. A day without entries returns zeros with the
-- user's goal (the default for their age when never set). With p_entry_id: that one entry only.
-- Errors: 42501 not the actor, P0001 UPGRADE_REQUIRED / ONBOARDING_INCOMPLETE.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION sleep.fn_summary(p_user_id uuid, p_date date, p_entry_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_goal integer;
    v_total integer;
    v_score integer;
    c record;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_timezone := sleep.fn_require_sleep(p_user_id);
    IF p_entry_id IS NOT NULL THEN
        SELECT e.wake_local_date INTO p_date FROM sleep.entry AS e
        WHERE e.id = p_entry_id AND e.user_id = p_user_id AND e.deleted_at IS NULL;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'sleep entry not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
        END IF;
    END IF;
    p_date := coalesce(p_date, common.fn_local_date(v_timezone));
    SELECT * INTO c FROM sleep.fn_constants();

    SELECT d.counted_min, d.score_pct, d.goal_min INTO v_total, v_score, v_goal
    FROM sleep.daily_summary AS d WHERE d.user_id = p_user_id AND d.local_date = p_date;
    IF NOT FOUND THEN
        v_total := 0;
        v_score := 0;
        SELECT coalesce(p.sleep_goal_min, (
            SELECT g.goal_min FROM ref.sleep_goal_by_age AS g WHERE p.age_years BETWEEN g.min_age AND g.max_age
        ), 480)
        INTO v_goal
        FROM app.user_profile AS p WHERE p.user_id = p_user_id;
    END IF;

    RETURN jsonb_build_object(
        'date', p_date,
        'counted_min', v_total,
        'goal_min', v_goal,
        'score_pct', v_score,
        'label', CASE
            WHEN v_total = 0 THEN 'none'
            WHEN v_score >= c.good_from_pct THEN 'good'
            WHEN v_score >= c.fair_from_pct THEN 'fair'
            ELSE 'low'
        END,
        'buffers', jsonb_build_object(
            'onset_min', c.onset_buffer_min, 'wake_min', c.wake_buffer_min,
            'waking_min', c.waking_fallback_min
        ),
        'entries', coalesce((
            SELECT jsonb_agg(jsonb_build_object(
                'entry_id', e.id,
                'sleep_start', e.sleep_start,
                'wake_time', e.wake_time,
                'counted_min', e.counted_min,
                'version', e.version,
                'editable', e.id IN (SELECT x FROM sleep.fn_editable_entry_ids(p_user_id) AS x),
                'wakings', coalesce((
                    SELECT jsonb_agg(jsonb_build_object('woke_at', w.woke_at, 'back_asleep_at', w.back_asleep_at)
                        ORDER BY w.woke_at)
                    FROM sleep.night_waking AS w WHERE w.entry_id = e.id
                ), '[]'::jsonb)
            ) ORDER BY e.wake_time, e.id)
            FROM sleep.entry AS e
            WHERE
                e.user_id = p_user_id AND e.wake_local_date = p_date AND e.deleted_at IS NULL
                AND (p_entry_id IS NULL OR e.id = p_entry_id)
        ), '[]'::jsonb)
    );
END
$$;

COMMENT ON FUNCTION sleep.fn_summary(uuid, date, uuid) IS
'STAR: a day''s sleep total, goal, score, label and entries with night wakings';
REVOKE ALL ON FUNCTION sleep.fn_summary(uuid, date, uuid) FROM public;
GRANT EXECUTE ON FUNCTION sleep.fn_summary(uuid, date, uuid) TO app_rw;
