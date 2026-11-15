-- GET /foods/barcode/{code} (doc 04 section 2.4, OQ-44): the cached product for a barcode, with the
-- linked food when the nutritionists mapped it. No row when unknown (the API then asks Open Food
-- Facts and caches the answer with nutrition.pr_upsert_barcode_product). The common.barcode
-- parameter type rejects anything but 8-14 digits (23514).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_barcode_lookup(p_barcode common.barcode)
RETURNS TABLE (
    barcode text,
    food_id uuid,
    product_name text,
    brand text,
    serving_g numeric,
    nutrients jsonb,
    source common.code,
    fetched_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        b.barcode::text, b.food_id, b.product_name::text, b.brand::text, b.serving_g,
        jsonb_strip_nulls(jsonb_build_object(
            'calories', b.calories_kcal, 'protein', b.protein_g, 'carbohydrates', b.carbohydrates_g,
            'fat', b.fat_g, 'dietary_fiber', b.dietary_fiber_g, 'total_sugar', b.total_sugar_g,
            'saturated_fat', b.saturated_fat_g, 'polyunsaturated_fat', b.polyunsaturated_fat_g,
            'monounsaturated_fat', b.monounsaturated_fat_g, 'trans_fat', b.trans_fat_g,
            'cholesterol', b.cholesterol_mg, 'sodium', b.sodium_mg, 'potassium', b.potassium_mg,
            'calcium', b.calcium_mg, 'iron', b.iron_mg, 'vitamin_a', b.vitamin_a_mcg,
            'vitamin_c', b.vitamin_c_mg
        )),
        b.source, b.fetched_at
    FROM nutrition.barcode_product AS b
    WHERE b.barcode = p_barcode AND b.deleted_at IS NULL;
$$;

COMMENT ON FUNCTION nutrition.fn_barcode_lookup(common.barcode) IS
'Cached packaged product by barcode (nutrients per 100 g; NULL when unknown are omitted)';
REVOKE ALL ON FUNCTION nutrition.fn_barcode_lookup(common.barcode) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_barcode_lookup(common.barcode) TO app_rw, app_readonly;
