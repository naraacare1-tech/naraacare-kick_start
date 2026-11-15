-- GET /foods/{food_id} (doc 04 section 2.4): an active food, its 17 nutrients per 100 g/ml and its
-- portions (nutrition.fn_food_portions). The API filters the nutrients by tier (6 vs 17).
-- No row for an unknown, retired or deleted food (the API answers 404).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_food_detail(p_food_id uuid)
RETURNS TABLE (
    food_id uuid,
    name text,
    category_code common.code,
    basis common.code,
    is_cooked boolean,
    nutrients jsonb,
    portions jsonb,
    aliases jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        f.id, f.name::text, f.category_code, f.basis, f.is_cooked,
        jsonb_build_object(
            'calories', f.calories_kcal, 'protein', f.protein_g, 'carbohydrates', f.carbohydrates_g,
            'fat', f.fat_g, 'dietary_fiber', f.dietary_fiber_g, 'total_sugar', f.total_sugar_g,
            'saturated_fat', f.saturated_fat_g, 'polyunsaturated_fat', f.polyunsaturated_fat_g,
            'monounsaturated_fat', f.monounsaturated_fat_g, 'trans_fat', f.trans_fat_g,
            'cholesterol', f.cholesterol_mg, 'sodium', f.sodium_mg, 'potassium', f.potassium_mg,
            'calcium', f.calcium_mg, 'iron', f.iron_mg, 'vitamin_a', f.vitamin_a_mcg,
            'vitamin_c', f.vitamin_c_mg
        ),
        (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'unit_code', p.unit_code, 'size', p.size, 'label', p.label,
                'quantity', p.quantity, 'basis', p.basis, 'is_default', p.is_default
            )), '[]'::jsonb)
            FROM nutrition.fn_food_portions(ARRAY[f.id]) AS p
        ),
        (
            SELECT coalesce(jsonb_agg(a.alias ORDER BY a.alias), '[]'::jsonb)
            FROM nutrition.food_alias AS a
            WHERE a.food_id = f.id AND a.deleted_at IS NULL
        )
    FROM nutrition.food_item AS f
    WHERE f.id = p_food_id AND f.status = 'active' AND f.deleted_at IS NULL;
$$;

COMMENT ON FUNCTION nutrition.fn_food_detail(uuid) IS 'Active food with 17 nutrients per 100 g/ml, portions and aliases';
REVOKE ALL ON FUNCTION nutrition.fn_food_detail(uuid) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_food_detail(uuid) TO app_rw, app_readonly;
