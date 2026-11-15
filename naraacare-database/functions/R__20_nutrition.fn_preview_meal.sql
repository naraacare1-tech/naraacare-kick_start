-- POST /meals?dry_run=true (Session 08, View Nutrition Summary on Add Meal): the same validation and
-- nutrient maths as nutrition.pr_log_meal, without saving anything or counting toward the daily
-- limit, so the app never computes nutrients itself. Returns one row per item plus the totals.
-- Errors: 22023 invalid items (as nutrition.fn_item_nutrients), 42501 not the actor.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_preview_meal(p_user_id uuid, p_items jsonb)
RETURNS TABLE (items jsonb, totals jsonb)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT
        jsonb_agg(
            jsonb_build_object(
                'food_id', n.food_id, 'food_name', n.food_name, 'quantity', n.quantity,
                'unit_code', n.unit_code, 'unit_size', n.unit_size, 'portion_label', n.portion_label,
                'consumed_amount', n.consumed_amount, 'consumed_basis', n.consumed_basis,
                'nutrients', jsonb_build_object(
                    'calories', n.calories_kcal, 'protein', n.protein_g, 'carbohydrates', n.carbohydrates_g,
                    'fat', n.fat_g, 'dietary_fiber', n.dietary_fiber_g, 'total_sugar', n.total_sugar_g,
                    'saturated_fat', n.saturated_fat_g, 'polyunsaturated_fat', n.polyunsaturated_fat_g,
                    'monounsaturated_fat', n.monounsaturated_fat_g, 'trans_fat', n.trans_fat_g,
                    'cholesterol', n.cholesterol_mg, 'sodium', n.sodium_mg, 'potassium', n.potassium_mg,
                    'calcium', n.calcium_mg, 'iron', n.iron_mg, 'vitamin_a', n.vitamin_a_mcg,
                    'vitamin_c', n.vitamin_c_mg
                )
            )
            ORDER BY n.item_no
        ),
        jsonb_build_object(
            'calories', sum(n.calories_kcal), 'protein', sum(n.protein_g),
            'carbohydrates', sum(n.carbohydrates_g), 'fat', sum(n.fat_g),
            'dietary_fiber', sum(n.dietary_fiber_g), 'total_sugar', sum(n.total_sugar_g),
            'saturated_fat', sum(n.saturated_fat_g), 'polyunsaturated_fat', sum(n.polyunsaturated_fat_g),
            'monounsaturated_fat', sum(n.monounsaturated_fat_g), 'trans_fat', sum(n.trans_fat_g),
            'cholesterol', sum(n.cholesterol_mg), 'sodium', sum(n.sodium_mg), 'potassium', sum(n.potassium_mg),
            'calcium', sum(n.calcium_mg), 'iron', sum(n.iron_mg), 'vitamin_a', sum(n.vitamin_a_mcg),
            'vitamin_c', sum(n.vitamin_c_mg)
        )
    FROM nutrition.fn_item_nutrients(p_items) AS n;
END
$$;

COMMENT ON FUNCTION nutrition.fn_preview_meal(uuid, jsonb) IS
'Dry run of a meal: per-item nutrients and totals, nothing saved, no limit counted';
REVOKE ALL ON FUNCTION nutrition.fn_preview_meal(uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_preview_meal(uuid, jsonb) TO app_rw;
