-- Portions available for foods (doc 06 section 2.10): the food's own nutrition.food_unit_override
-- rows replace the category defaults (ref.food_category_unit) unit by unit; units without an
-- override keep the category rows. Used by GET /foods/{id}, search results (default portion) and
-- the meal maths (nutrition.fn_item_nutrients). Reference data only: no user rows, no actor check.
-- Served by the PKs of food_unit_override and food_category_unit.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_food_portions(p_food_ids uuid[])
RETURNS TABLE (
    food_id uuid,
    unit_code common.code,
    size common.code,
    label text,
    quantity numeric,
    basis common.code,
    is_default boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    WITH foods AS (
        SELECT f.id, f.category_code
        FROM nutrition.food_item AS f
        WHERE f.id = ANY (p_food_ids) AND f.deleted_at IS NULL
    ),
    rows AS (
        -- Food-specific portions; one of them is the default when the category default uses that unit.
        SELECT
            f.id AS food_id, o.unit_code, o.size, o.quantity, o.basis,
            EXISTS (
                SELECT 1 FROM ref.food_category_unit AS d
                WHERE d.category_code = f.category_code AND d.unit_code = o.unit_code AND d.is_default
            )
            AND o.size = (
                SELECT o2.size FROM nutrition.food_unit_override AS o2
                WHERE o2.food_id = f.id AND o2.unit_code = o.unit_code
                ORDER BY (o2.size IN ('medium', 'standard')) DESC, o2.size
                LIMIT 1
            ) AS is_default
        FROM foods AS f
        INNER JOIN nutrition.food_unit_override AS o ON o.food_id = f.id
        UNION ALL
        -- Category defaults for units the food does not override.
        SELECT f.id, c.unit_code, c.size, c.quantity, c.basis, c.is_default
        FROM foods AS f
        INNER JOIN ref.food_category_unit AS c ON c.category_code = f.category_code
        WHERE NOT EXISTS (
            SELECT 1 FROM nutrition.food_unit_override AS o
            WHERE o.food_id = f.id AND o.unit_code = c.unit_code
        )
    )
    SELECT
        r.food_id,
        r.unit_code::common.code,
        r.size::common.code,
        CASE WHEN r.size = 'standard' THEN u.label ELSE initcap(r.size) || ' ' || u.label END,
        r.quantity,
        r.basis::common.code,
        r.is_default
    FROM rows AS r
    INNER JOIN ref.unit AS u ON u.code = r.unit_code
    ORDER BY r.food_id, r.is_default DESC, u.label, r.quantity;
$$;

COMMENT ON FUNCTION nutrition.fn_food_portions(uuid[]) IS
'Portions per food: overrides replace category defaults per unit; one default per food';
REVOKE ALL ON FUNCTION nutrition.fn_food_portions(uuid[]) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_food_portions(uuid[]) TO app_rw, app_readonly;
