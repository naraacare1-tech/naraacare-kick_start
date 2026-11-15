-- Internal building blocks for the meal read functions and the edit rule (doc 06 section 2.11,
-- OQ-53). Not granted to any login role; called from the definer functions/procedures, which run as
-- api_definer under RLS (own rows only).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Edit window: only the user's last 2 non-deleted meals (by logged_at) are editable, and only while
-- they were logged within the last 7 days.
CREATE OR REPLACE FUNCTION nutrition.fn_editable_meal_ids(p_user_id uuid)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT m.id
    FROM (
        SELECT m.id, m.logged_at
        FROM nutrition.meal AS m
        WHERE m.user_id = p_user_id AND m.deleted_at IS NULL
        ORDER BY m.logged_at DESC
        LIMIT 2
    ) AS m
    WHERE m.logged_at > now() - interval '7 days';
$$;

COMMENT ON FUNCTION nutrition.fn_editable_meal_ids(uuid) IS
'Internal: ids of the meals still editable (last 2 by logged_at, within 7 days)';
REVOKE ALL ON FUNCTION nutrition.fn_editable_meal_ids(uuid) FROM public;

-- Meals with their items and nutrient totals (17 nutrients; the API filters by tier).
CREATE OR REPLACE FUNCTION nutrition.fn_meal_rows(p_user_id uuid, p_meal_ids uuid[])
RETURNS TABLE (
    meal_id uuid,
    logged_at timestamptz,
    local_date date,
    meal_type common.code,
    source common.code,
    version integer,
    hydration_credit boolean,
    editable boolean,
    totals jsonb,
    items jsonb,
    updated_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    WITH editable AS (SELECT e AS id FROM nutrition.fn_editable_meal_ids(p_user_id) AS e)
    SELECT
        m.id, m.logged_at, m.local_date, m.meal_type, m.source, m.version, m.hydration_credit,
        m.id IN (SELECT e.id FROM editable AS e),
        jsonb_build_object(
            'calories', sum(i.calories_kcal), 'protein', sum(i.protein_g),
            'carbohydrates', sum(i.carbohydrates_g), 'fat', sum(i.fat_g),
            'dietary_fiber', sum(i.dietary_fiber_g), 'total_sugar', sum(i.total_sugar_g),
            'saturated_fat', sum(i.saturated_fat_g), 'polyunsaturated_fat', sum(i.polyunsaturated_fat_g),
            'monounsaturated_fat', sum(i.monounsaturated_fat_g), 'trans_fat', sum(i.trans_fat_g),
            'cholesterol', sum(i.cholesterol_mg), 'sodium', sum(i.sodium_mg),
            'potassium', sum(i.potassium_mg), 'calcium', sum(i.calcium_mg), 'iron', sum(i.iron_mg),
            'vitamin_a', sum(i.vitamin_a_mcg), 'vitamin_c', sum(i.vitamin_c_mg)
        ),
        jsonb_agg(
            jsonb_build_object(
                'item_id', i.id, 'food_id', i.food_id, 'food_name', f.name, 'quantity', i.quantity,
                'unit_code', i.unit_code, 'unit_size', i.unit_size,
                'consumed_amount', i.consumed_amount, 'consumed_basis', i.consumed_basis,
                'nutrients', jsonb_build_object(
                    'calories', i.calories_kcal, 'protein', i.protein_g,
                    'carbohydrates', i.carbohydrates_g, 'fat', i.fat_g,
                    'dietary_fiber', i.dietary_fiber_g, 'total_sugar', i.total_sugar_g,
                    'saturated_fat', i.saturated_fat_g, 'polyunsaturated_fat', i.polyunsaturated_fat_g,
                    'monounsaturated_fat', i.monounsaturated_fat_g, 'trans_fat', i.trans_fat_g,
                    'cholesterol', i.cholesterol_mg, 'sodium', i.sodium_mg,
                    'potassium', i.potassium_mg, 'calcium', i.calcium_mg, 'iron', i.iron_mg,
                    'vitamin_a', i.vitamin_a_mcg, 'vitamin_c', i.vitamin_c_mg
                )
            )
            ORDER BY i.created_at, i.id
        ),
        m.updated_at
    FROM nutrition.meal AS m
    INNER JOIN nutrition.meal_item AS i
        ON i.meal_id = m.id AND i.meal_logged_at = m.logged_at AND i.deleted_at IS NULL
    INNER JOIN nutrition.food_item AS f ON f.id = i.food_id
    WHERE m.user_id = p_user_id AND m.id = ANY (p_meal_ids) AND m.deleted_at IS NULL
    GROUP BY m.id, m.logged_at
    ORDER BY m.logged_at DESC;
$$;

COMMENT ON FUNCTION nutrition.fn_meal_rows(uuid, uuid[]) IS
'Internal: meals with items, 17-nutrient totals and the editable flag';
REVOKE ALL ON FUNCTION nutrition.fn_meal_rows(uuid, uuid[]) FROM public;
