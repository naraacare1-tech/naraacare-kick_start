-- POST /meals (doc 04 section 2.4, doc 06 section 2.11). Saves one meal with its item snapshots.
--   * Idempotent: p_meal_id is the app's client_entry_id; a replay returns o_status = 'duplicate'
--     and changes nothing (offline sync, retries).
--   * Day: the local date of p_logged_at in the user's timezone. Backdating up to 7 days (OQ-53);
--     older -> EDIT_WINDOW_CLOSED; more than 5 minutes in the future -> 22023 LOGGED_AT_INVALID.
--   * Limit: the user's daily_summary row for that day is created if needed and locked (FOR UPDATE)
--     before counting, so two devices posting at 3/4 cannot both succeed (OQ-09: 4 STANDARD, 8 STAR).
--   * Source voice/barcode needs the STAR entitlement (also checked by the API) -> UPGRADE_REQUIRED.
--   * Then: items with nutrient snapshots, summary + hydration credits rebuilt, activity day marked.
-- Errors: 22023 (items, logged_at), P0001 DAILY_LIMIT_REACHED / EDIT_WINDOW_CLOSED / UPGRADE_REQUIRED /
--         ONBOARDING_INCOMPLETE, 42501 not the actor.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE nutrition.pr_log_meal(
    p_user_id uuid,
    p_meal_id uuid,
    p_logged_at timestamptz,
    p_meal_type common.code,
    p_source common.code,
    p_items jsonb,
    INOUT o_status text DEFAULT NULL,
    INOUT o_local_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_timezone common.iana_timezone;
    v_today date;
    v_count smallint;
    v_limit integer;
    v_features jsonb;
    v_summary jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_meal_id IS NULL OR p_logged_at IS NULL OR p_meal_type IS NULL OR p_source IS NULL THEN
        RAISE EXCEPTION 'meal id, time, type and source are required' USING ERRCODE = '22023', DETAIL = 'MEAL_INVALID';
    END IF;

    -- Replay of an already saved meal (any day): nothing to do.
    SELECT m.local_date INTO o_local_date
    FROM nutrition.meal AS m WHERE m.id = p_meal_id AND m.user_id = p_user_id;
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
    v_today := common.fn_local_date(v_timezone);
    IF o_local_date < v_today - 7 THEN
        RAISE EXCEPTION 'entries older than 7 days cannot be added'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    SELECT e.features, (e.limits ->> 'meal_logs_per_day')::integer INTO v_features, v_limit
    FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF (p_source = 'voice' AND NOT coalesce((v_features ->> 'voice_logging')::boolean, FALSE))
       OR (p_source = 'barcode' AND NOT coalesce((v_features ->> 'barcode_logging')::boolean, FALSE)) THEN
        RAISE EXCEPTION 'this source needs STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;

    INSERT INTO nutrition.daily_summary (user_id, local_date)
    VALUES (p_user_id, o_local_date)
    ON CONFLICT (user_id, local_date) DO NOTHING;
    SELECT d.meal_count INTO v_count
    FROM nutrition.daily_summary AS d
    WHERE d.user_id = p_user_id AND d.local_date = o_local_date
    FOR UPDATE;
    IF v_count >= coalesce(v_limit, 4) THEN
        RAISE EXCEPTION 'daily meal limit reached' USING ERRCODE = 'P0001', DETAIL = 'DAILY_LIMIT_REACHED';
    END IF;

    INSERT INTO nutrition.meal (id, logged_at, user_id, local_date, meal_type, source, created_by, updated_by)
    VALUES (p_meal_id, p_logged_at, p_user_id, o_local_date, p_meal_type, p_source, p_user_id, p_user_id);

    INSERT INTO nutrition.meal_item (
        meal_id, meal_logged_at, user_id, food_id, quantity, unit_code, unit_size,
        consumed_amount, consumed_basis,
        calories_kcal, protein_g, carbohydrates_g, fat_g, dietary_fiber_g, total_sugar_g,
        saturated_fat_g, polyunsaturated_fat_g, monounsaturated_fat_g, trans_fat_g, cholesterol_mg,
        sodium_mg, potassium_mg, calcium_mg, iron_mg, vitamin_a_mcg, vitamin_c_mg,
        created_at, created_by, updated_by
    )
    SELECT
        p_meal_id, p_logged_at, p_user_id, n.food_id, n.quantity, n.unit_code, n.unit_size,
        n.consumed_amount, n.consumed_basis,
        n.calories_kcal, n.protein_g, n.carbohydrates_g, n.fat_g, n.dietary_fiber_g, n.total_sugar_g,
        n.saturated_fat_g, n.polyunsaturated_fat_g, n.monounsaturated_fat_g, n.trans_fat_g, n.cholesterol_mg,
        n.sodium_mg, n.potassium_mg, n.calcium_mg, n.iron_mg, n.vitamin_a_mcg, n.vitamin_c_mg,
        clock_timestamp() + n.item_no * interval '1 microsecond', p_user_id, p_user_id
    FROM nutrition.fn_item_nutrients(p_items) AS n;

    CALL nutrition.pr_refresh_daily_summary(p_user_id, o_local_date);

    INSERT INTO app.user_activity_day (user_id, local_date, has_nutrition)
    VALUES (p_user_id, o_local_date, TRUE)
    ON CONFLICT (user_id, local_date) DO UPDATE SET has_nutrition = TRUE;

    IF o_local_date = common.fn_local_date(v_timezone) THEN
        -- CALL arguments cannot contain subqueries (0A000): build the summary first.
        SELECT jsonb_build_object('meal_type', p_meal_type, 'kcal', round(coalesce(sum(i.calories_kcal), 0))::integer)
        INTO v_summary
        FROM nutrition.meal_item AS i
        WHERE i.meal_id = p_meal_id AND i.meal_logged_at = p_logged_at;
        CALL social.pr_emit_activity(p_user_id, 'nutrition', 'logged', v_summary);
    END IF;
    o_status := 'created';
END
$$;

COMMENT ON PROCEDURE nutrition.pr_log_meal (uuid, uuid, timestamptz, common.code, common.code, jsonb, text, date) IS
'Save a meal (idempotent by client id) under the daily-limit lock; snapshots, summary, credits';
REVOKE ALL ON PROCEDURE nutrition.pr_log_meal(uuid, uuid, timestamptz, common.code, common.code, jsonb, text, date)
FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_log_meal(uuid, uuid, timestamptz, common.code, common.code, jsonb, text, date)
TO app_rw;
