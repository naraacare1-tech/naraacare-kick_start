-- POST /saved-meals and DELETE /saved-meals/{id} (doc 04 section 2.4): meal templates, max 50 per
-- user. Items are checked like meal items (active food, offered unit/size, quantity 0.25..20 in
-- 0.25 steps) through nutrition.fn_item_nutrients; no nutrients are stored (computed when logged).
-- The name is checked by common.fn_validate_text (safe text, 1..60; never echoed).
-- Errors: 22023 invalid name/items, P0001 SAVED_MEAL_LIMIT, 42501 not the actor / not found.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE nutrition.pr_save_meal_template(
    p_user_id uuid,
    p_name text,
    p_items jsonb,
    INOUT o_saved_meal_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_name common.safe_text;
    v_count integer;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_name := common.fn_validate_text(btrim(p_name), 60);
    IF v_name IS NULL OR char_length(v_name) = 0 THEN
        RAISE EXCEPTION 'name is required' USING ERRCODE = '22023', DETAIL = 'NAME_REQUIRED';
    END IF;
    -- Serialise per user so the cap holds under concurrent requests.
    PERFORM 1 FROM auth.user_account AS a WHERE a.id = p_user_id FOR UPDATE;
    SELECT count(*) INTO v_count FROM nutrition.saved_meal AS s
    WHERE s.user_id = p_user_id AND s.deleted_at IS NULL;
    IF v_count >= 50 THEN
        RAISE EXCEPTION 'at most 50 saved meals' USING ERRCODE = 'P0001', DETAIL = 'SAVED_MEAL_LIMIT';
    END IF;

    INSERT INTO nutrition.saved_meal (user_id, name, created_by, updated_by)
    VALUES (p_user_id, v_name, p_user_id, p_user_id)
    RETURNING id INTO o_saved_meal_id;

    INSERT INTO nutrition.saved_meal_item (saved_meal_id, user_id, food_id, quantity, unit_code, unit_size, created_at)
    SELECT o_saved_meal_id, p_user_id, n.food_id, n.quantity, n.unit_code, n.unit_size,
           clock_timestamp() + n.item_no * interval '1 microsecond'
    FROM nutrition.fn_item_nutrients(p_items) AS n;
END
$$;

COMMENT ON PROCEDURE nutrition.pr_save_meal_template (uuid, text, jsonb, uuid) IS
'Save a meal template (max 50 per user); items validated like meal items';
REVOKE ALL ON PROCEDURE nutrition.pr_save_meal_template(uuid, text, jsonb, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_save_meal_template(uuid, text, jsonb, uuid) TO app_rw;

CREATE OR REPLACE PROCEDURE nutrition.pr_delete_saved_meal(p_user_id uuid, p_saved_meal_id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE nutrition.saved_meal AS s
    SET deleted_at = now(), updated_by = p_user_id
    WHERE s.id = p_saved_meal_id AND s.user_id = p_user_id AND s.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'saved meal not found' USING ERRCODE = '42501';
    END IF;
END
$$;

COMMENT ON PROCEDURE nutrition.pr_delete_saved_meal (uuid, uuid) IS 'Soft-delete one of the actor''s saved meals';
REVOKE ALL ON PROCEDURE nutrition.pr_delete_saved_meal(uuid, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_delete_saved_meal(uuid, uuid) TO app_rw;
