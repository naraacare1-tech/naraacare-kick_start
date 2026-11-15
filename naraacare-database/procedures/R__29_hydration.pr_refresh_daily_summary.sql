-- Internal: rebuild one day's hydration.daily_summary totals from the non-deleted drinks and
-- workouts of that local date (doc 05 section 8: maintained aggregate, same transaction as the
-- write). Enforces the swipe-down rule (doc 06 section 3.6): the day's water volume can never go
-- below 0, whichever write (log, edit, delete) would cause it -> P0001 WATER_BELOW_ZERO, and the
-- caller's whole transaction rolls back.
-- Callers hold the day's summary row lock (SELECT ... FOR UPDATE), so totals cannot interleave.
-- Not granted to any login role: called from the definer procedures (run as api_definer, RLS on).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE hydration.pr_lock_daily_summary(p_user_id uuid, p_date date)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    INSERT INTO hydration.daily_summary (user_id, local_date)
    VALUES (p_user_id, p_date)
    ON CONFLICT (user_id, local_date) DO NOTHING;
    PERFORM 1 FROM hydration.daily_summary AS d
    WHERE d.user_id = p_user_id AND d.local_date = p_date
    FOR UPDATE;
END
$$;

COMMENT ON PROCEDURE hydration.pr_lock_daily_summary (uuid, date) IS
'Internal: create if needed and lock a day''s hydration summary row (serialises writes for that day)';
REVOKE ALL ON PROCEDURE hydration.pr_lock_daily_summary(uuid, date) FROM public;

CREATE OR REPLACE PROCEDURE hydration.pr_refresh_daily_summary(p_user_id uuid, p_date date)
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_water integer;
    v_volume integer;
    v_effective numeric;
    v_sweat numeric;
BEGIN
    SELECT
        coalesce(sum(i.volume_ml) FILTER (WHERE i.drink_code = 'water'), 0),
        coalesce(sum(i.volume_ml), 0),
        coalesce(sum(i.effective_ml), 0)
    INTO v_water, v_volume, v_effective
    FROM hydration.intake AS i
    WHERE i.user_id = p_user_id AND i.local_date = p_date AND i.deleted_at IS NULL;
    IF v_water < 0 THEN
        RAISE EXCEPTION 'the day''s water cannot go below 0'
            USING ERRCODE = 'P0001', DETAIL = 'WATER_BELOW_ZERO';
    END IF;

    SELECT coalesce(sum(w.sweat_ml), 0) INTO v_sweat
    FROM activity.workout AS w
    WHERE w.user_id = p_user_id AND w.local_date = p_date AND w.deleted_at IS NULL;

    UPDATE hydration.daily_summary AS d
    SET volume_ml = v_volume, effective_intake_ml = v_effective, workout_sweat_ml = v_sweat,
        updated_at = now()
    WHERE d.user_id = p_user_id AND d.local_date = p_date;
END
$$;

COMMENT ON PROCEDURE hydration.pr_refresh_daily_summary (uuid, date) IS
'Internal: rebuild a day''s drink and sweat totals; rejects a negative day water volume';
REVOKE ALL ON PROCEDURE hydration.pr_refresh_daily_summary(uuid, date) FROM public;
