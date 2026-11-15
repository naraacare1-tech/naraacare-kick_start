-- POST /hydration/intakes (doc 04 section 2.5, doc 06 section 3.6). Saves one drink.
--   * Idempotent: p_intake_id is the app's client_entry_id; a replay returns o_status = 'duplicate'.
--   * Exactly one of p_drink_code / p_custom_drink_id. STAR drinks need premium_drinks, custom
--     drinks need custom_drinks (UPGRADE_REQUIRED); a custom drink must be the caller's (-> 404).
--   * volume 1..3000 mL, or -100 for a swipe-down on water (also a table CHECK); the day's water
--     volume can never go below 0 (WATER_BELOW_ZERO, under the day's summary row lock).
--   * The factor is snapshotted with the drink, so later factor changes never rewrite history.
--   * Day: local date of p_logged_at; backdating up to 7 days (EDIT_WINDOW_CLOSED), at most
--     5 minutes in the future (22023 LOGGED_AT_INVALID). Marks the activity day (streaks).
-- Errors: 22023, P0001 UPGRADE_REQUIRED / WATER_BELOW_ZERO / EDIT_WINDOW_CLOSED / ONBOARDING_INCOMPLETE,
--         42501 not the actor or not the caller's custom drink.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal: factor of a drink the caller may use now (tier checks); shared by log and edit.
CREATE OR REPLACE FUNCTION hydration.fn_usable_drink_factor(
    p_user_id uuid, p_drink_code common.code, p_custom_drink_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_features jsonb;
    v_factor numeric(4, 3);
    v_tier common.code;
BEGIN
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF p_drink_code IS NOT NULL THEN
        SELECT t.hydration_factor, t.tier_required INTO v_factor, v_tier
        FROM ref.drink_type AS t WHERE t.code = p_drink_code;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'unknown drink' USING ERRCODE = '22023', DETAIL = 'DRINK_INVALID';
        END IF;
        IF v_tier <> 'standard' AND NOT coalesce((v_features ->> 'premium_drinks')::boolean, FALSE) THEN
            RAISE EXCEPTION 'this drink needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
        END IF;
        RETURN v_factor;
    END IF;
    IF NOT coalesce((v_features ->> 'custom_drinks')::boolean, FALSE) THEN
        RAISE EXCEPTION 'custom drinks need STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;
    SELECT c.hydration_factor INTO v_factor
    FROM hydration.custom_drink AS c
    WHERE c.id = p_custom_drink_id AND c.user_id = p_user_id AND c.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'custom drink not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;
    RETURN v_factor;
END
$$;

COMMENT ON FUNCTION hydration.fn_usable_drink_factor(uuid, common.code, uuid) IS
'Internal: hydration factor of a drink the caller may log now (STAR drinks and custom drinks checked)';
REVOKE ALL ON FUNCTION hydration.fn_usable_drink_factor(uuid, common.code, uuid) FROM public;

CREATE OR REPLACE PROCEDURE hydration.pr_log_intake(
    p_user_id uuid,
    p_intake_id uuid,
    p_logged_at timestamptz,
    p_drink_code common.code,
    p_custom_drink_id uuid,
    p_volume_ml integer,
    p_source common.code,
    INOUT o_status text DEFAULT NULL,
    INOUT o_local_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_factor numeric(4, 3);
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_intake_id IS NULL OR p_logged_at IS NULL OR p_volume_ml IS NULL OR p_source IS NULL
       OR num_nonnulls(p_drink_code, p_custom_drink_id) <> 1 THEN
        RAISE EXCEPTION 'intake id, time, one drink, volume and source are required'
            USING ERRCODE = '22023', DETAIL = 'INTAKE_INVALID';
    END IF;
    IF NOT (p_volume_ml BETWEEN 1 AND 3000
            OR (p_volume_ml = -100 AND p_source = 'swipe' AND p_drink_code = 'water')) THEN
        RAISE EXCEPTION 'volume must be 1..3000 mL (or -100 for a water swipe)'
            USING ERRCODE = '22023', DETAIL = 'VOLUME_INVALID';
    END IF;

    SELECT i.local_date INTO o_local_date
    FROM hydration.intake AS i WHERE i.id = p_intake_id AND i.user_id = p_user_id;
    IF FOUND THEN
        o_status := 'duplicate';
        RETURN;
    END IF;

    SELECT p.timezone INTO v_timezone
    FROM app.user_profile AS p
    WHERE p.user_id = p_user_id AND p.onboarding_completed_at IS NOT NULL AND p.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'complete onboarding first' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    IF p_logged_at > now() + interval '5 minutes' THEN
        RAISE EXCEPTION 'logged_at is in the future' USING ERRCODE = '22023', DETAIL = 'LOGGED_AT_INVALID';
    END IF;
    o_local_date := common.fn_local_date(v_timezone, p_logged_at);
    IF o_local_date < common.fn_local_date(v_timezone) - 7 THEN
        RAISE EXCEPTION 'entries older than 7 days cannot be added'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    v_factor := hydration.fn_usable_drink_factor(p_user_id, p_drink_code, p_custom_drink_id);

    CALL hydration.pr_lock_daily_summary(p_user_id, o_local_date);

    INSERT INTO hydration.intake (
        id, logged_at, user_id, local_date, drink_code, custom_drink_id, volume_ml, hydration_factor,
        effective_ml, source, created_by, updated_by
    )
    VALUES (
        p_intake_id, p_logged_at, p_user_id, o_local_date, p_drink_code, p_custom_drink_id, p_volume_ml,
        v_factor, round(p_volume_ml * v_factor, 1), p_source, p_user_id, p_user_id
    );

    CALL hydration.pr_refresh_daily_summary(p_user_id, o_local_date);

    INSERT INTO app.user_activity_day (user_id, local_date, has_hydration)
    VALUES (p_user_id, o_local_date, TRUE)
    ON CONFLICT (user_id, local_date) DO UPDATE SET has_hydration = TRUE;

    IF o_local_date = common.fn_local_date(v_timezone) THEN
        CALL social.pr_emit_activity(
            p_user_id, 'hydration', 'logged',
            jsonb_build_object('volume_ml', p_volume_ml, 'drink_code', coalesce(p_drink_code, 'custom'))
        );
    END IF;
    o_status := 'created';
END
$$;

COMMENT ON PROCEDURE hydration.pr_log_intake (uuid, uuid, timestamptz, common.code, uuid, integer, common.code, text, date) IS
'Save a drink (idempotent by client id): tier check, factor snapshot, day water never below 0';
REVOKE ALL ON PROCEDURE hydration.pr_log_intake(uuid, uuid, timestamptz, common.code, uuid, integer, common.code, text, date)
FROM public;
GRANT EXECUTE ON PROCEDURE hydration.pr_log_intake(uuid, uuid, timestamptz, common.code, uuid, integer, common.code, text, date)
TO app_rw;
