-- PUT /meals/{id} and DELETE /meals/{id} (doc 04 section 2.4). Optimistic concurrency with the
-- version the client last saw (If-Match); only the last 2 meals within 7 days may change (OQ-53).
-- The day's summary row is locked first, then items are replaced (new snapshots) or the meal is
-- soft-deleted, and the day's totals and hydration credits are rebuilt.
-- Errors: 42501 meal not found / not the actor's (-> 404), P0001 VERSION_CONFLICT / EDIT_WINDOW_CLOSED,
--         22023 invalid items.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE nutrition.pr_update_meal(
    p_user_id uuid,
    p_meal_id uuid,
    p_expected_version integer,
    p_meal_type common.code,
    p_items jsonb,
    INOUT o_version integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_meal nutrition.meal%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_meal FROM nutrition.meal AS m
    WHERE m.id = p_meal_id AND m.user_id = p_user_id AND m.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'meal not found' USING ERRCODE = '42501';
    END IF;
    PERFORM 1 FROM nutrition.daily_summary AS d
    WHERE d.user_id = p_user_id AND d.local_date = v_meal.local_date FOR UPDATE;
    SELECT * INTO v_meal FROM nutrition.meal AS m
    WHERE m.id = p_meal_id AND m.logged_at = v_meal.logged_at AND m.deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'meal not found' USING ERRCODE = '42501';
    END IF;
    IF p_expected_version IS DISTINCT FROM v_meal.version THEN
        RAISE EXCEPTION 'meal was changed elsewhere' USING ERRCODE = 'P0001', DETAIL = 'VERSION_CONFLICT';
    END IF;
    IF p_meal_id NOT IN (SELECT e FROM nutrition.fn_editable_meal_ids(p_user_id) AS e) THEN
        RAISE EXCEPTION 'only the last 2 meals within 7 days can be edited'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    IF p_items IS NOT NULL THEN
        DELETE FROM nutrition.meal_item AS i
        WHERE i.meal_id = p_meal_id AND i.meal_logged_at = v_meal.logged_at;
        INSERT INTO nutrition.meal_item (
            meal_id, meal_logged_at, user_id, food_id, quantity, unit_code, unit_size,
            consumed_amount, consumed_basis,
            calories_kcal, protein_g, carbohydrates_g, fat_g, dietary_fiber_g, total_sugar_g,
            saturated_fat_g, polyunsaturated_fat_g, monounsaturated_fat_g, trans_fat_g, cholesterol_mg,
            sodium_mg, potassium_mg, calcium_mg, iron_mg, vitamin_a_mcg, vitamin_c_mg,
            created_at, created_by, updated_by
        )
        SELECT
            p_meal_id, v_meal.logged_at, p_user_id, n.food_id, n.quantity, n.unit_code, n.unit_size,
            n.consumed_amount, n.consumed_basis,
            n.calories_kcal, n.protein_g, n.carbohydrates_g, n.fat_g, n.dietary_fiber_g, n.total_sugar_g,
            n.saturated_fat_g, n.polyunsaturated_fat_g, n.monounsaturated_fat_g, n.trans_fat_g, n.cholesterol_mg,
            n.sodium_mg, n.potassium_mg, n.calcium_mg, n.iron_mg, n.vitamin_a_mcg, n.vitamin_c_mg,
            clock_timestamp() + n.item_no * interval '1 microsecond', p_user_id, p_user_id
        FROM nutrition.fn_item_nutrients(p_items) AS n;
    END IF;

    UPDATE nutrition.meal AS m
    SET meal_type = coalesce(p_meal_type, m.meal_type), version = m.version + 1, updated_by = p_user_id,
        updated_at = now()
    WHERE m.id = p_meal_id AND m.logged_at = v_meal.logged_at
    RETURNING m.version INTO o_version;

    CALL nutrition.pr_refresh_daily_summary(p_user_id, v_meal.local_date);
END
$$;

COMMENT ON PROCEDURE nutrition.pr_update_meal (uuid, uuid, integer, common.code, jsonb, integer) IS
'Edit one of the last 2 meals (If-Match version): new item snapshots, summary rebuilt';
REVOKE ALL ON PROCEDURE nutrition.pr_update_meal(uuid, uuid, integer, common.code, jsonb, integer) FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_update_meal(uuid, uuid, integer, common.code, jsonb, integer) TO app_rw;

CREATE OR REPLACE PROCEDURE nutrition.pr_delete_meal(
    p_user_id uuid,
    p_meal_id uuid,
    p_expected_version integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_meal nutrition.meal%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_meal FROM nutrition.meal AS m
    WHERE m.id = p_meal_id AND m.user_id = p_user_id AND m.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'meal not found' USING ERRCODE = '42501';
    END IF;
    PERFORM 1 FROM nutrition.daily_summary AS d
    WHERE d.user_id = p_user_id AND d.local_date = v_meal.local_date FOR UPDATE;
    SELECT * INTO v_meal FROM nutrition.meal AS m
    WHERE m.id = p_meal_id AND m.logged_at = v_meal.logged_at AND m.deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'meal not found' USING ERRCODE = '42501';
    END IF;
    IF p_expected_version IS DISTINCT FROM v_meal.version THEN
        RAISE EXCEPTION 'meal was changed elsewhere' USING ERRCODE = 'P0001', DETAIL = 'VERSION_CONFLICT';
    END IF;
    IF p_meal_id NOT IN (SELECT e FROM nutrition.fn_editable_meal_ids(p_user_id) AS e) THEN
        RAISE EXCEPTION 'only the last 2 meals within 7 days can be deleted'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;

    UPDATE nutrition.meal_item AS i
    SET deleted_at = now(), updated_by = p_user_id
    WHERE i.meal_id = p_meal_id AND i.meal_logged_at = v_meal.logged_at AND i.deleted_at IS NULL;
    UPDATE nutrition.meal AS m
    SET deleted_at = now(), hydration_credit = FALSE, version = m.version + 1, updated_by = p_user_id
    WHERE m.id = p_meal_id AND m.logged_at = v_meal.logged_at;

    CALL nutrition.pr_refresh_daily_summary(p_user_id, v_meal.local_date);
END
$$;

COMMENT ON PROCEDURE nutrition.pr_delete_meal (uuid, uuid, integer) IS
'Soft-delete one of the last 2 meals (If-Match version); summary and hydration credits rebuilt';
REVOKE ALL ON PROCEDURE nutrition.pr_delete_meal(uuid, uuid, integer) FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_delete_meal(uuid, uuid, integer) TO app_rw;
