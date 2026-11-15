-- POST/PUT/DELETE /sleep/entries (doc 04 section 2.6, doc 06 section 4, OQ-23). STAR only (`sleep`).
--   * Validation: wake > start, at most 16 h (sleep.max_entry_hours), wake <= now + 5 minutes; at most
--     10 night wakings, each inside the interval, woke < back asleep, in order and not overlapping.
--   * counted_min is computed here from the calc constants and snapshotted with the buffers used.
--   * The entry belongs to the local date of its wake time; backdating up to 7 days.
--   * Overlapping entries are impossible: the exclusion constraint ex_sleep_entry__no_overlap raises
--     23P01, reported as P0001 SLEEP_OVERLAP.
--   * Idempotent create by client id (o_status 'duplicate'); edit/delete: If-Match version, last 2
--     entries within 7 days. Both affected days' summaries are rebuilt; the activity day is marked.
-- Errors: 42501 not the actor / not found, 22023 invalid, P0001 UPGRADE_REQUIRED / SLEEP_OVERLAP /
--         EDIT_WINDOW_CLOSED / VERSION_CONFLICT / ONBOARDING_INCOMPLETE.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal: STAR + onboarding check; returns the user's timezone.
CREATE OR REPLACE FUNCTION sleep.fn_require_sleep(p_user_id uuid)
RETURNS common.iana_timezone
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_features jsonb;
BEGIN
    SELECT p.timezone INTO v_timezone
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF NOT coalesce((v_features ->> 'sleep')::boolean, FALSE) THEN
        RAISE EXCEPTION 'sleep needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;
    RETURN v_timezone;
END
$$;

COMMENT ON FUNCTION sleep.fn_require_sleep(uuid) IS 'Internal: STAR sleep entitlement and onboarding check; the user''s timezone';
REVOKE ALL ON FUNCTION sleep.fn_require_sleep(uuid) FROM public;

-- Internal: validate an entry and its wakings (22023 with a DETAIL code).
CREATE OR REPLACE FUNCTION sleep.fn_validate_entry(
    p_start timestamptz, p_wake timestamptz, p_wakings jsonb, p_max_hours integer
)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_item jsonb;
    v_key text;
    v_woke timestamptz;
    v_back timestamptz;
    v_prev timestamptz;
BEGIN
    IF p_start IS NULL OR p_wake IS NULL OR p_wake <= p_start THEN
        RAISE EXCEPTION 'wake time must be after sleep start' USING ERRCODE = '22023', DETAIL = 'SLEEP_INVALID';
    END IF;
    IF p_wake - p_start > make_interval(hours => p_max_hours) THEN
        RAISE EXCEPTION 'an entry can be at most % hours', p_max_hours USING ERRCODE = '22023', DETAIL = 'SLEEP_TOO_LONG';
    END IF;
    IF p_wake > now() + interval '5 minutes' THEN
        RAISE EXCEPTION 'wake time is in the future' USING ERRCODE = '22023', DETAIL = 'LOGGED_AT_INVALID';
    END IF;
    IF p_wakings IS NULL OR jsonb_typeof(p_wakings) <> 'array' OR jsonb_array_length(p_wakings) > 10 THEN
        RAISE EXCEPTION 'at most 10 night wakings' USING ERRCODE = '22023', DETAIL = 'WAKINGS_INVALID';
    END IF;
    v_prev := p_start;
    FOR v_item IN SELECT value FROM jsonb_array_elements(p_wakings) LOOP
        IF jsonb_typeof(v_item) <> 'object' THEN
            RAISE EXCEPTION 'a night waking must be an object' USING ERRCODE = '22023', DETAIL = 'WAKINGS_INVALID';
        END IF;
        FOR v_key IN SELECT jsonb_object_keys(v_item) LOOP
            IF v_key NOT IN ('woke_at', 'back_asleep_at') THEN
                RAISE EXCEPTION 'unknown night waking field' USING ERRCODE = '22023', DETAIL = 'WAKINGS_INVALID';
            END IF;
        END LOOP;
        v_woke := (v_item ->> 'woke_at')::timestamptz;
        v_back := (v_item ->> 'back_asleep_at')::timestamptz;
        IF v_woke IS NULL OR v_back IS NULL OR v_back <= v_woke OR v_woke < v_prev OR v_back > p_wake THEN
            RAISE EXCEPTION 'night wakings must be inside the sleep, in order and not overlapping'
                USING ERRCODE = '22023', DETAIL = 'WAKINGS_INVALID';
        END IF;
        v_prev := v_back;
    END LOOP;
END
$$;

COMMENT ON FUNCTION sleep.fn_validate_entry(timestamptz, timestamptz, jsonb, integer) IS
'Internal: sleep entry and night waking validation (doc 06 section 4)';
REVOKE ALL ON FUNCTION sleep.fn_validate_entry(timestamptz, timestamptz, jsonb, integer) FROM public;

CREATE OR REPLACE PROCEDURE sleep.pr_log_entry(
    p_user_id uuid,
    p_entry_id uuid,
    p_sleep_start timestamptz,
    p_wake_time timestamptz,
    p_wakings jsonb,
    INOUT o_status text DEFAULT NULL,
    INOUT o_local_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    c record;
    v_summary jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_entry_id IS NULL THEN
        RAISE EXCEPTION 'entry id is required' USING ERRCODE = '22023', DETAIL = 'SLEEP_INVALID';
    END IF;
    v_timezone := sleep.fn_require_sleep(p_user_id);

    SELECT e.wake_local_date INTO o_local_date
    FROM sleep.entry AS e WHERE e.id = p_entry_id AND e.user_id = p_user_id;
    IF FOUND THEN
        o_status := 'duplicate';
        RETURN;
    END IF;

    SELECT * INTO c FROM sleep.fn_constants();
    PERFORM sleep.fn_validate_entry(p_sleep_start, p_wake_time, coalesce(p_wakings, '[]'), c.max_entry_hours);
    o_local_date := common.fn_local_date(v_timezone, p_wake_time);
    IF o_local_date < common.fn_local_date(v_timezone) - 7 THEN
        RAISE EXCEPTION 'entries older than 7 days cannot be added'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    BEGIN
        INSERT INTO sleep.entry (
            id, user_id, sleep_start, wake_time, wake_local_date, onset_buffer_min, wake_buffer_min,
            counted_min, created_by, updated_by
        )
        VALUES (
            p_entry_id, p_user_id, p_sleep_start, p_wake_time, o_local_date, c.onset_buffer_min,
            c.wake_buffer_min,
            sleep.fn_counted_min(
                p_sleep_start, p_wake_time, coalesce(p_wakings, '[]'), c.onset_buffer_min,
                c.wake_buffer_min, c.waking_fallback_min
            ),
            p_user_id, p_user_id
        );
    EXCEPTION WHEN exclusion_violation THEN
        RAISE EXCEPTION 'this sleep overlaps another entry' USING ERRCODE = 'P0001', DETAIL = 'SLEEP_OVERLAP';
    END;
    INSERT INTO sleep.night_waking (entry_id, user_id, woke_at, back_asleep_at)
    SELECT p_entry_id, p_user_id, (w ->> 'woke_at')::timestamptz, (w ->> 'back_asleep_at')::timestamptz
    FROM jsonb_array_elements(coalesce(p_wakings, '[]')) AS w;

    CALL sleep.pr_refresh_daily_summary(p_user_id, o_local_date);
    INSERT INTO app.user_activity_day (user_id, local_date, has_sleep)
    VALUES (p_user_id, o_local_date, TRUE)
    ON CONFLICT (user_id, local_date) DO UPDATE SET has_sleep = TRUE;
    IF o_local_date = common.fn_local_date(v_timezone) THEN
        -- CALL arguments cannot contain subqueries (0A000): build the summary first.
        SELECT jsonb_build_object('counted_min', e.counted_min) INTO v_summary FROM sleep.entry AS e WHERE e.id = p_entry_id;
        CALL social.pr_emit_activity(p_user_id, 'sleep', 'logged', v_summary);
    END IF;
    o_status := 'created';
END
$$;

COMMENT ON PROCEDURE sleep.pr_log_entry (uuid, uuid, timestamptz, timestamptz, jsonb, text, date) IS
'STAR: save a sleep entry with night wakings (idempotent by client id); counted minutes and summary';
REVOKE ALL ON PROCEDURE sleep.pr_log_entry(uuid, uuid, timestamptz, timestamptz, jsonb, text, date) FROM public;
GRANT EXECUTE ON PROCEDURE sleep.pr_log_entry(uuid, uuid, timestamptz, timestamptz, jsonb, text, date) TO app_rw;

-- Internal: find, lock and check the entry the caller may change.
CREATE OR REPLACE FUNCTION sleep.fn_lock_editable_entry(p_user_id uuid, p_entry_id uuid, p_expected_version integer)
RETURNS sleep.entry
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row sleep.entry%ROWTYPE;
BEGIN
    SELECT * INTO v_row FROM sleep.entry AS e
    WHERE e.id = p_entry_id AND e.user_id = p_user_id AND e.deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'sleep entry not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;
    IF p_expected_version IS DISTINCT FROM v_row.version THEN
        RAISE EXCEPTION 'entry was changed elsewhere' USING ERRCODE = 'P0001', DETAIL = 'VERSION_CONFLICT';
    END IF;
    IF p_entry_id NOT IN (SELECT x FROM sleep.fn_editable_entry_ids(p_user_id) AS x) THEN
        RAISE EXCEPTION 'only the last 2 entries within 7 days can change'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;
    RETURN v_row;
END
$$;

COMMENT ON FUNCTION sleep.fn_lock_editable_entry(uuid, uuid, integer) IS
'Internal: lock a sleep entry the caller may edit (exists, version matches, last 2 within 7 days)';
REVOKE ALL ON FUNCTION sleep.fn_lock_editable_entry(uuid, uuid, integer) FROM public;

CREATE OR REPLACE PROCEDURE sleep.pr_update_entry(
    p_user_id uuid,
    p_entry_id uuid,
    p_expected_version integer,
    p_sleep_start timestamptz,
    p_wake_time timestamptz,
    p_wakings jsonb,
    INOUT o_version integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_row sleep.entry%ROWTYPE;
    v_date date;
    c record;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_timezone := sleep.fn_require_sleep(p_user_id);
    v_row := sleep.fn_lock_editable_entry(p_user_id, p_entry_id, p_expected_version);
    SELECT * INTO c FROM sleep.fn_constants();
    PERFORM sleep.fn_validate_entry(p_sleep_start, p_wake_time, coalesce(p_wakings, '[]'), c.max_entry_hours);
    v_date := common.fn_local_date(v_timezone, p_wake_time);
    IF v_date < common.fn_local_date(v_timezone) - 7 THEN
        RAISE EXCEPTION 'entries older than 7 days cannot be changed'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    BEGIN
        UPDATE sleep.entry AS e
        SET sleep_start = p_sleep_start, wake_time = p_wake_time, wake_local_date = v_date,
            onset_buffer_min = c.onset_buffer_min, wake_buffer_min = c.wake_buffer_min,
            counted_min = sleep.fn_counted_min(
                p_sleep_start, p_wake_time, coalesce(p_wakings, '[]'), c.onset_buffer_min,
                c.wake_buffer_min, c.waking_fallback_min
            ),
            version = e.version + 1, updated_by = p_user_id, updated_at = now()
        WHERE e.id = p_entry_id
        RETURNING e.version INTO o_version;
    EXCEPTION WHEN exclusion_violation THEN
        RAISE EXCEPTION 'this sleep overlaps another entry' USING ERRCODE = 'P0001', DETAIL = 'SLEEP_OVERLAP';
    END;
    DELETE FROM sleep.night_waking AS w WHERE w.entry_id = p_entry_id;
    INSERT INTO sleep.night_waking (entry_id, user_id, woke_at, back_asleep_at)
    SELECT p_entry_id, p_user_id, (w ->> 'woke_at')::timestamptz, (w ->> 'back_asleep_at')::timestamptz
    FROM jsonb_array_elements(coalesce(p_wakings, '[]')) AS w;

    CALL sleep.pr_refresh_daily_summary(p_user_id, v_row.wake_local_date);
    IF v_date <> v_row.wake_local_date THEN
        CALL sleep.pr_refresh_daily_summary(p_user_id, v_date);
        INSERT INTO app.user_activity_day (user_id, local_date, has_sleep)
        VALUES (p_user_id, v_date, TRUE)
        ON CONFLICT (user_id, local_date) DO UPDATE SET has_sleep = TRUE;
    END IF;
END
$$;

COMMENT ON PROCEDURE sleep.pr_update_entry (uuid, uuid, integer, timestamptz, timestamptz, jsonb, integer) IS
'STAR: edit one of the last 2 sleep entries (If-Match version); counted minutes and summaries rebuilt';
REVOKE ALL ON PROCEDURE sleep.pr_update_entry(uuid, uuid, integer, timestamptz, timestamptz, jsonb, integer) FROM public;
GRANT EXECUTE ON PROCEDURE sleep.pr_update_entry(uuid, uuid, integer, timestamptz, timestamptz, jsonb, integer) TO app_rw;

CREATE OR REPLACE PROCEDURE sleep.pr_delete_entry(p_user_id uuid, p_entry_id uuid, p_expected_version integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row sleep.entry%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    PERFORM sleep.fn_require_sleep(p_user_id);
    v_row := sleep.fn_lock_editable_entry(p_user_id, p_entry_id, p_expected_version);
    UPDATE sleep.entry AS e
    SET deleted_at = now(), version = e.version + 1, updated_by = p_user_id, updated_at = now()
    WHERE e.id = p_entry_id;
    CALL sleep.pr_refresh_daily_summary(p_user_id, v_row.wake_local_date);
END
$$;

COMMENT ON PROCEDURE sleep.pr_delete_entry (uuid, uuid, integer) IS
'STAR: soft-delete one of the last 2 sleep entries (If-Match version); summary rebuilt';
REVOKE ALL ON PROCEDURE sleep.pr_delete_entry(uuid, uuid, integer) FROM public;
GRANT EXECUTE ON PROCEDURE sleep.pr_delete_entry(uuid, uuid, integer) TO app_rw;
