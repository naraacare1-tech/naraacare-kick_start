-- Cache of a barcode product fetched from Open Food Facts by the API (OQ-44). The API validates the
-- response first (product name SafeShortText, else "Unnamed product"; numbers within the column
-- ranges); the table domains and CHECKs reject anything else. Only open_food_facts rows are written
-- here: internal rows are curated by nutritionists and never overwritten by this procedure.
-- p_nutrients: per 100 g, keys as in nutrition.pr_admin_upsert_food; missing keys stay NULL (unknown).
-- Any signed-in user may trigger the cache (the lookup itself is STAR, checked by the API).
-- Meals reference foods, so a product with known calories also gets a food_item in the 'packaged'
-- category (source_ref "Open Food Facts (ODbL)", unknown nutrients stored as 0) with a "serving"
-- portion of serving_g (else the category's 100 g). Packaged foods are not offered in name search.
-- Data that breaks the food CHECKs (e.g. macros > 100 g) leaves the product unlinked (not loggable).
-- o_food_id returns the linked food (NULL when not loggable).
-- Errors: 22023 invalid text/nutrients, 23514 invalid barcode or out-of-range values.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE nutrition.pr_upsert_barcode_product(
    p_actor_id uuid,
    p_barcode common.barcode,
    p_product_name text,
    p_brand text,
    p_serving_g numeric,
    p_nutrients jsonb,
    INOUT o_food_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_name common.safe_text := common.fn_validate_text(btrim(p_product_name), 160);
    v_brand common.safe_text := CASE WHEN p_brand IS NULL THEN NULL ELSE common.fn_validate_text(btrim(p_brand), 80) END;
    v_n jsonb := coalesce(p_nutrients, '{}'::jsonb);
BEGIN
    PERFORM common.fn_assert_actor(p_actor_id);
    IF jsonb_typeof(v_n) <> 'object'
       OR EXISTS (SELECT 1 FROM jsonb_each(v_n) AS e WHERE jsonb_typeof(e.value) <> 'number') THEN
        RAISE EXCEPTION 'nutrients must be numbers' USING ERRCODE = '22023', DETAIL = 'NUTRIENTS_INVALID';
    END IF;
    INSERT INTO nutrition.barcode_product AS b (
        barcode, product_name, brand, serving_g,
        calories_kcal, protein_g, carbohydrates_g, fat_g, dietary_fiber_g, total_sugar_g, saturated_fat_g,
        polyunsaturated_fat_g, monounsaturated_fat_g, trans_fat_g, cholesterol_mg, sodium_mg,
        potassium_mg, calcium_mg, iron_mg, vitamin_a_mcg, vitamin_c_mg,
        source, fetched_at, created_by, updated_by
    )
    VALUES (
        p_barcode, v_name, nullif(v_brand, ''), p_serving_g,
        (v_n ->> 'calories')::numeric, (v_n ->> 'protein')::numeric, (v_n ->> 'carbohydrates')::numeric,
        (v_n ->> 'fat')::numeric, (v_n ->> 'dietary_fiber')::numeric, (v_n ->> 'total_sugar')::numeric,
        (v_n ->> 'saturated_fat')::numeric, (v_n ->> 'polyunsaturated_fat')::numeric,
        (v_n ->> 'monounsaturated_fat')::numeric, (v_n ->> 'trans_fat')::numeric,
        (v_n ->> 'cholesterol')::numeric, (v_n ->> 'sodium')::numeric, (v_n ->> 'potassium')::numeric,
        (v_n ->> 'calcium')::numeric, (v_n ->> 'iron')::numeric, (v_n ->> 'vitamin_a')::numeric,
        (v_n ->> 'vitamin_c')::numeric,
        'open_food_facts', now(), p_actor_id, p_actor_id
    )
    ON CONFLICT (barcode) DO UPDATE SET
        product_name = excluded.product_name, brand = excluded.brand, serving_g = excluded.serving_g,
        calories_kcal = excluded.calories_kcal, protein_g = excluded.protein_g,
        carbohydrates_g = excluded.carbohydrates_g, fat_g = excluded.fat_g,
        dietary_fiber_g = excluded.dietary_fiber_g, total_sugar_g = excluded.total_sugar_g,
        saturated_fat_g = excluded.saturated_fat_g, polyunsaturated_fat_g = excluded.polyunsaturated_fat_g,
        monounsaturated_fat_g = excluded.monounsaturated_fat_g, trans_fat_g = excluded.trans_fat_g,
        cholesterol_mg = excluded.cholesterol_mg, sodium_mg = excluded.sodium_mg,
        potassium_mg = excluded.potassium_mg, calcium_mg = excluded.calcium_mg, iron_mg = excluded.iron_mg,
        vitamin_a_mcg = excluded.vitamin_a_mcg, vitamin_c_mg = excluded.vitamin_c_mg,
        fetched_at = excluded.fetched_at, updated_by = excluded.updated_by, deleted_at = NULL
    WHERE b.source = 'open_food_facts';

    SELECT b.food_id INTO o_food_id FROM nutrition.barcode_product AS b WHERE b.barcode = p_barcode;
    IF o_food_id IS NOT NULL OR (v_n ->> 'calories') IS NULL
       OR (SELECT b.source FROM nutrition.barcode_product AS b WHERE b.barcode = p_barcode) <> 'open_food_facts' THEN
        RETURN;
    END IF;
    BEGIN
        INSERT INTO nutrition.food_item (
            name, category_code, basis, is_cooked, source_ref,
            calories_kcal, protein_g, carbohydrates_g, fat_g, dietary_fiber_g, total_sugar_g,
            saturated_fat_g, polyunsaturated_fat_g, monounsaturated_fat_g, trans_fat_g, cholesterol_mg,
            sodium_mg, potassium_mg, calcium_mg, iron_mg, vitamin_a_mcg, vitamin_c_mg,
            created_by, updated_by
        )
        VALUES (
            common.fn_validate_text(left(v_name, 120), 120), 'packaged', 'g', FALSE, 'Open Food Facts (ODbL)',
            coalesce((v_n ->> 'calories')::numeric, 0), coalesce((v_n ->> 'protein')::numeric, 0),
            coalesce((v_n ->> 'carbohydrates')::numeric, 0), coalesce((v_n ->> 'fat')::numeric, 0),
            coalesce((v_n ->> 'dietary_fiber')::numeric, 0), coalesce((v_n ->> 'total_sugar')::numeric, 0),
            coalesce((v_n ->> 'saturated_fat')::numeric, 0), coalesce((v_n ->> 'polyunsaturated_fat')::numeric, 0),
            coalesce((v_n ->> 'monounsaturated_fat')::numeric, 0), coalesce((v_n ->> 'trans_fat')::numeric, 0),
            coalesce((v_n ->> 'cholesterol')::numeric, 0), coalesce((v_n ->> 'sodium')::numeric, 0),
            coalesce((v_n ->> 'potassium')::numeric, 0), coalesce((v_n ->> 'calcium')::numeric, 0),
            coalesce((v_n ->> 'iron')::numeric, 0), coalesce((v_n ->> 'vitamin_a')::numeric, 0),
            coalesce((v_n ->> 'vitamin_c')::numeric, 0),
            p_actor_id, p_actor_id
        )
        RETURNING id INTO o_food_id;
        IF p_serving_g IS NOT NULL AND p_serving_g <= 2000 THEN
            INSERT INTO nutrition.food_unit_override (food_id, unit_code, size, quantity, basis)
            VALUES (o_food_id, 'serving', 'standard', round(p_serving_g, 1), 'g');
        END IF;
        UPDATE nutrition.barcode_product AS b SET food_id = o_food_id WHERE b.barcode = p_barcode;
    EXCEPTION WHEN check_violation THEN
        o_food_id := NULL;
    END;
END
$$;

COMMENT ON PROCEDURE nutrition.pr_upsert_barcode_product (uuid, common.barcode, text, text, numeric, jsonb, uuid) IS
'Cache an Open Food Facts product by barcode and link a loggable packaged food (never overwrites curated rows)';
REVOKE ALL ON PROCEDURE nutrition.pr_upsert_barcode_product(uuid, common.barcode, text, text, numeric, jsonb, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_upsert_barcode_product(uuid, common.barcode, text, text, numeric, jsonb, uuid) TO app_rw;
