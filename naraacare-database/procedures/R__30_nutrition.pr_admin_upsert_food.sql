-- POST /admin/foods and PATCH /admin/foods/{id} (doc 04 section 2.16, OQ-42): nutritionists maintain
-- the food database. Also used by tools/import_food_csv.py. The actor must hold the nutritionist
-- (or admin) role; anyone else gets 42501 (-> 404). Texts go through common.fn_validate_text (safe
-- text + length) and nutrient ranges through the table CHECKs; the audit trigger on food_item records
-- every change with the actor.
--   p_food_id NULL      -> create (o_food_id = new id)
--   p_food_id given     -> full replace of that food's fields
--   p_nutrients         -> {"calories": 52, "protein": 0.3, ...} per 100 g/ml; missing keys = 0
--   p_aliases           -> ["Chapati", "Phulka"] replaces the alias set (1..60 chars each, max 20)
--   p_alias_language    -> en | hi | hinglish for new aliases
-- Errors: 22023 invalid text/nutrients, 23503 unknown category, 23514 out-of-range values, 42501.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE nutrition.pr_admin_upsert_food(
    p_actor_id uuid,
    p_food_id uuid,
    p_name text,
    p_category_code common.code,
    p_basis common.code,
    p_density_g_per_ml numeric,
    p_is_cooked boolean,
    p_source_ref text,
    p_nutrients jsonb,
    p_aliases jsonb,
    p_alias_language common.code DEFAULT 'hinglish',
    INOUT o_food_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_name common.safe_text;
    v_source common.safe_text;
    v_n jsonb := coalesce(p_nutrients, '{}'::jsonb);
    v_known text[] := ARRAY[
        'calories', 'protein', 'carbohydrates', 'fat', 'dietary_fiber', 'total_sugar', 'saturated_fat',
        'polyunsaturated_fat', 'monounsaturated_fat', 'trans_fat', 'cholesterol', 'sodium', 'potassium',
        'calcium', 'iron', 'vitamin_a', 'vitamin_c'
    ];
BEGIN
    PERFORM common.fn_assert_actor(p_actor_id);
    IF NOT EXISTS (
        SELECT 1 FROM auth.user_account AS a
        WHERE a.id = p_actor_id AND a.role IN ('nutritionist', 'admin') AND a.status = 'active'
    ) THEN
        RAISE EXCEPTION 'not allowed' USING ERRCODE = '42501';
    END IF;
    v_name := common.fn_validate_text(btrim(p_name), 120);
    v_source := common.fn_validate_text(btrim(p_source_ref), 120);
    IF jsonb_typeof(v_n) <> 'object'
       OR EXISTS (SELECT 1 FROM jsonb_object_keys(v_n) AS k WHERE k <> ALL (v_known))
       OR EXISTS (SELECT 1 FROM jsonb_each(v_n) AS e WHERE jsonb_typeof(e.value) <> 'number')
    THEN
        RAISE EXCEPTION 'nutrients must be numbers keyed by nutrient code'
            USING ERRCODE = '22023', DETAIL = 'NUTRIENTS_INVALID';
    END IF;
    IF p_aliases IS NOT NULL AND (
        jsonb_typeof(p_aliases) <> 'array' OR jsonb_array_length(p_aliases) > 20
        OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_aliases) AS e WHERE jsonb_typeof(e.value) <> 'string')
    ) THEN
        RAISE EXCEPTION 'aliases must be up to 20 strings' USING ERRCODE = '22023', DETAIL = 'ALIASES_INVALID';
    END IF;

    IF p_food_id IS NULL THEN
        INSERT INTO nutrition.food_item (name, category_code, basis, density_g_per_ml, is_cooked, source_ref, created_by, updated_by)
        VALUES (v_name, p_category_code, p_basis, coalesce(p_density_g_per_ml, 1.000), p_is_cooked, v_source, p_actor_id, p_actor_id)
        RETURNING id INTO o_food_id;
    ELSE
        UPDATE nutrition.food_item AS f
        SET name = v_name, category_code = p_category_code, basis = p_basis,
            density_g_per_ml = coalesce(p_density_g_per_ml, 1.000), is_cooked = p_is_cooked,
            source_ref = v_source, updated_by = p_actor_id
        WHERE f.id = p_food_id AND f.deleted_at IS NULL
        RETURNING f.id INTO o_food_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'food not found' USING ERRCODE = '42501';
        END IF;
    END IF;

    UPDATE nutrition.food_item AS f
    SET calories_kcal = coalesce((v_n ->> 'calories')::numeric, 0),
        protein_g = coalesce((v_n ->> 'protein')::numeric, 0),
        carbohydrates_g = coalesce((v_n ->> 'carbohydrates')::numeric, 0),
        fat_g = coalesce((v_n ->> 'fat')::numeric, 0),
        dietary_fiber_g = coalesce((v_n ->> 'dietary_fiber')::numeric, 0),
        total_sugar_g = coalesce((v_n ->> 'total_sugar')::numeric, 0),
        saturated_fat_g = coalesce((v_n ->> 'saturated_fat')::numeric, 0),
        polyunsaturated_fat_g = coalesce((v_n ->> 'polyunsaturated_fat')::numeric, 0),
        monounsaturated_fat_g = coalesce((v_n ->> 'monounsaturated_fat')::numeric, 0),
        trans_fat_g = coalesce((v_n ->> 'trans_fat')::numeric, 0),
        cholesterol_mg = coalesce((v_n ->> 'cholesterol')::numeric, 0),
        sodium_mg = coalesce((v_n ->> 'sodium')::numeric, 0),
        potassium_mg = coalesce((v_n ->> 'potassium')::numeric, 0),
        calcium_mg = coalesce((v_n ->> 'calcium')::numeric, 0),
        iron_mg = coalesce((v_n ->> 'iron')::numeric, 0),
        vitamin_a_mcg = coalesce((v_n ->> 'vitamin_a')::numeric, 0),
        vitamin_c_mg = coalesce((v_n ->> 'vitamin_c')::numeric, 0)
    WHERE f.id = o_food_id;

    IF p_aliases IS NOT NULL THEN
        UPDATE nutrition.food_alias AS a
        SET deleted_at = now(), updated_by = p_actor_id
        WHERE a.food_id = o_food_id AND a.deleted_at IS NULL
          AND a.alias_normalized NOT IN (
              SELECT lower(btrim(e.value)) FROM jsonb_array_elements_text(p_aliases) AS e (value)
          );
        INSERT INTO nutrition.food_alias (food_id, alias, language, created_by, updated_by)
        SELECT o_food_id, common.fn_validate_text(btrim(e.value), 60), p_alias_language, p_actor_id, p_actor_id
        FROM jsonb_array_elements_text(p_aliases) AS e (value)
        WHERE NOT EXISTS (
            SELECT 1 FROM nutrition.food_alias AS a
            WHERE a.food_id = o_food_id AND a.deleted_at IS NULL AND a.alias_normalized = lower(btrim(e.value))
        );
    END IF;
END
$$;

COMMENT ON PROCEDURE nutrition.pr_admin_upsert_food (uuid, uuid, text, common.code, common.code, numeric, boolean, text, jsonb, jsonb, common.code, uuid) IS
'Nutritionist create/replace of a food (17 nutrients per 100 g/ml, source_ref, aliases)';
REVOKE ALL ON PROCEDURE nutrition.pr_admin_upsert_food(uuid, uuid, text, common.code, common.code, numeric, boolean, text, jsonb, jsonb, common.code, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE nutrition.pr_admin_upsert_food(uuid, uuid, text, common.code, common.code, numeric, boolean, text, jsonb, jsonb, common.code, uuid) TO app_rw;
