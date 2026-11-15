-- Internal: the nutrient snapshot of meal items (doc 06 section 2.10). Single source of the meal
-- maths, used by nutrition.pr_log_meal, nutrition.pr_update_meal and the dry-run preview, so the
-- app and the API never compute nutrients themselves.
--   amount     = quantity x portion quantity, converted to the food's basis with density_g_per_ml
--                when the portion basis differs (ml portion of a g food: x density; g of an ml food: / density)
--   multiplier = amount / 100;  nutrient = per_100 x multiplier, kept at 3 decimals
-- p_items: [{food_id, quantity, unit_code, unit_size?}] (1..30). quantity 0.25..20 in steps of 0.25.
-- unit_size defaults to the default size of that unit for the food (else medium / standard).
-- Errors: 22023 MEAL_ITEMS_INVALID / FOOD_NOT_AVAILABLE / PORTION_NOT_AVAILABLE (the API answers 422).
-- Not granted to any login role: called from the definer procedures, which run as api_definer.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_item_nutrients(p_items jsonb)
RETURNS TABLE (
    item_no integer,
    food_id uuid,
    food_name text,
    quantity numeric,
    unit_code common.code,
    unit_size common.code,
    portion_label text,
    consumed_amount numeric,
    consumed_basis common.code,
    calories_kcal numeric,
    protein_g numeric,
    carbohydrates_g numeric,
    fat_g numeric,
    dietary_fiber_g numeric,
    total_sugar_g numeric,
    saturated_fat_g numeric,
    polyunsaturated_fat_g numeric,
    monounsaturated_fat_g numeric,
    trans_fat_g numeric,
    cholesterol_mg numeric,
    sodium_mg numeric,
    potassium_mg numeric,
    calcium_mg numeric,
    iron_mg numeric,
    vitamin_a_mcg numeric,
    vitamin_c_mg numeric
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_count integer;
BEGIN
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'items must be an array' USING ERRCODE = '22023', DETAIL = 'MEAL_ITEMS_INVALID';
    END IF;
    v_count := jsonb_array_length(p_items);
    IF v_count NOT BETWEEN 1 AND 30 THEN
        RAISE EXCEPTION 'a meal has 1..30 items' USING ERRCODE = '22023', DETAIL = 'MEAL_ITEMS_INVALID';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_items) AS e (value)
        WHERE jsonb_typeof(e.value) <> 'object'
           OR NOT (e.value ?& ARRAY['food_id', 'quantity', 'unit_code'])
           OR jsonb_typeof(e.value -> 'quantity') <> 'number'
           OR (e.value ->> 'quantity')::numeric NOT BETWEEN 0.25 AND 20
           OR (e.value ->> 'quantity')::numeric % 0.25 <> 0
    ) THEN
        RAISE EXCEPTION 'invalid item' USING ERRCODE = '22023', DETAIL = 'MEAL_ITEMS_INVALID';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_items) AS e (value)
        LEFT JOIN nutrition.food_item AS f
            ON f.id = (e.value ->> 'food_id')::uuid AND f.status = 'active' AND f.deleted_at IS NULL
        WHERE f.id IS NULL
    ) THEN
        RAISE EXCEPTION 'food not available' USING ERRCODE = '22023', DETAIL = 'FOOD_NOT_AVAILABLE';
    END IF;

    RETURN QUERY
    WITH items AS (
        SELECT
            e.ord::integer AS item_no,
            (e.value ->> 'food_id')::uuid AS food_id,
            (e.value ->> 'quantity')::numeric AS quantity,
            e.value ->> 'unit_code' AS unit_code,
            e.value ->> 'unit_size' AS unit_size
        FROM jsonb_array_elements(p_items) WITH ORDINALITY AS e (value, ord)
    ),
    portions AS (
        SELECT * FROM nutrition.fn_food_portions(ARRAY(SELECT DISTINCT i.food_id FROM items AS i))
    ),
    chosen AS (
        SELECT
            i.item_no, i.food_id, i.quantity,
            p.unit_code AS p_unit, p.size AS p_size, p.label AS p_label,
            p.quantity AS portion_qty, p.basis AS portion_basis
        FROM items AS i
        LEFT JOIN LATERAL (
            SELECT p.*
            FROM portions AS p
            WHERE p.food_id = i.food_id
              AND p.unit_code = i.unit_code
              AND (i.unit_size IS NULL OR p.size = i.unit_size)
            ORDER BY p.is_default DESC, (p.size IN ('medium', 'standard')) DESC, p.size
            LIMIT 1
        ) AS p ON TRUE
    ),
    amounts AS (
        SELECT
            c.item_no, c.food_id, c.quantity, c.p_unit, c.p_size, c.p_label, c.portion_qty,
            f.name::text AS food_name, f.basis AS food_basis,
            CASE
                WHEN c.portion_basis = f.basis THEN c.quantity * c.portion_qty
                WHEN c.portion_basis = 'ml' THEN c.quantity * c.portion_qty * f.density_g_per_ml
                ELSE c.quantity * c.portion_qty / f.density_g_per_ml
            END AS amount,
            f.calories_kcal AS k, f.protein_g AS pr, f.carbohydrates_g AS cb, f.fat_g AS ft,
            f.dietary_fiber_g AS fb, f.total_sugar_g AS sg, f.saturated_fat_g AS sf,
            f.polyunsaturated_fat_g AS pf, f.monounsaturated_fat_g AS mf, f.trans_fat_g AS tf,
            f.cholesterol_mg AS ch, f.sodium_mg AS na, f.potassium_mg AS po, f.calcium_mg AS ca,
            f.iron_mg AS fe, f.vitamin_a_mcg AS va, f.vitamin_c_mg AS vc
        FROM chosen AS c
        INNER JOIN nutrition.food_item AS f ON f.id = c.food_id
    )
    SELECT
        a.item_no, a.food_id, a.food_name, a.quantity,
        a.p_unit::common.code, a.p_size::common.code, a.p_label,
        round(a.amount, 1), a.food_basis::common.code,
        round(a.k * a.amount / 100, 3), round(a.pr * a.amount / 100, 3),
        round(a.cb * a.amount / 100, 3), round(a.ft * a.amount / 100, 3),
        round(a.fb * a.amount / 100, 3), round(a.sg * a.amount / 100, 3),
        round(a.sf * a.amount / 100, 3), round(a.pf * a.amount / 100, 3),
        round(a.mf * a.amount / 100, 3), round(a.tf * a.amount / 100, 3),
        round(a.ch * a.amount / 100, 3), round(a.na * a.amount / 100, 3),
        round(a.po * a.amount / 100, 3), round(a.ca * a.amount / 100, 3),
        round(a.fe * a.amount / 100, 3), round(a.va * a.amount / 100, 3),
        round(a.vc * a.amount / 100, 3)
    FROM amounts AS a
    WHERE a.portion_qty IS NOT NULL
    ORDER BY a.item_no;

    -- An item whose unit/size the food does not offer produced no row above.
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count <> jsonb_array_length(p_items) THEN
        RAISE EXCEPTION 'portion not available' USING ERRCODE = '22023', DETAIL = 'PORTION_NOT_AVAILABLE';
    END IF;
END
$$;

COMMENT ON FUNCTION nutrition.fn_item_nutrients(jsonb) IS
'Internal: per-item amount and 17-nutrient snapshot for meal items (the only meal maths)';
REVOKE ALL ON FUNCTION nutrition.fn_item_nutrients(jsonb) FROM public;
