-- Meal reads for the signed-in user (doc 04 section 2.4): GET /meals?date=, GET /meals/recent,
-- GET /meals/{id}/breakdown and the recent-food chips on Add Meal. Each asserts the actor (42501 ->
-- 404) and reads under RLS. Served by ix_meal__user_day and ix_meal_item__user_food_recent.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Meals of one local day, newest first.
CREATE OR REPLACE FUNCTION nutrition.fn_meals_by_date(p_user_id uuid, p_date date)
RETURNS TABLE (
    meal_id uuid, logged_at timestamptz, local_date date, meal_type common.code, source common.code,
    version integer, hydration_credit boolean, editable boolean, totals jsonb, items jsonb,
    updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT * FROM nutrition.fn_meal_rows(
        p_user_id,
        ARRAY(
            SELECT m.id FROM nutrition.meal AS m
            WHERE m.user_id = p_user_id AND m.local_date = p_date AND m.deleted_at IS NULL
        )
    );
END
$$;

COMMENT ON FUNCTION nutrition.fn_meals_by_date(uuid, date) IS 'Meals of one local day with items, totals and the editable flag';
REVOKE ALL ON FUNCTION nutrition.fn_meals_by_date(uuid, date) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_meals_by_date(uuid, date) TO app_rw, app_readonly;

-- Recent Updates (N9): the latest meals (1..10), the first two carry editable = true.
CREATE OR REPLACE FUNCTION nutrition.fn_recent_meals(p_user_id uuid, p_limit integer DEFAULT 10)
RETURNS TABLE (
    meal_id uuid, logged_at timestamptz, local_date date, meal_type common.code, source common.code,
    version integer, hydration_credit boolean, editable boolean, totals jsonb, items jsonb,
    updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT * FROM nutrition.fn_meal_rows(
        p_user_id,
        ARRAY(
            SELECT m.id FROM nutrition.meal AS m
            WHERE m.user_id = p_user_id AND m.deleted_at IS NULL
            ORDER BY m.logged_at DESC
            LIMIT least(greatest(coalesce(p_limit, 10), 1), 10)
        )
    );
END
$$;

COMMENT ON FUNCTION nutrition.fn_recent_meals(uuid, integer) IS 'Latest meals (max 10) with items, totals and the editable flag';
REVOKE ALL ON FUNCTION nutrition.fn_recent_meals(uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_recent_meals(uuid, integer) TO app_rw, app_readonly;

-- Recent food chips: distinct foods from the user's last 30 days, most recent first, with the
-- portion last used.
CREATE OR REPLACE FUNCTION nutrition.fn_recent_foods(p_user_id uuid, p_limit integer DEFAULT 10)
RETURNS TABLE (
    food_id uuid, name text, quantity numeric, unit_code common.code, unit_size common.code,
    last_logged_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT r.food_id, r.name, r.quantity, r.unit_code, r.unit_size, r.meal_logged_at
    FROM (
        SELECT DISTINCT ON (i.food_id)
            i.food_id, f.name::text AS name, i.quantity, i.unit_code, i.unit_size, i.meal_logged_at
        FROM nutrition.meal_item AS i
        INNER JOIN nutrition.food_item AS f ON f.id = i.food_id AND f.status = 'active' AND f.deleted_at IS NULL
        WHERE i.user_id = p_user_id AND i.deleted_at IS NULL
          AND i.meal_logged_at > now() - interval '30 days'
        ORDER BY i.food_id, i.meal_logged_at DESC
    ) AS r
    ORDER BY r.meal_logged_at DESC, r.name
    LIMIT least(greatest(coalesce(p_limit, 10), 1), 20);
END
$$;

COMMENT ON FUNCTION nutrition.fn_recent_foods(uuid, integer) IS 'Recent food chips (last 30 days) with the portion last used';
REVOKE ALL ON FUNCTION nutrition.fn_recent_foods(uuid, integer) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_recent_foods(uuid, integer) TO app_rw, app_readonly;

-- Meal-by-meal breakdown (STAR, OQ-11; the API checks the entitlement): one meal with items and
-- 17-nutrient totals. No row when the meal is not the actor's or is deleted (-> 404).
CREATE OR REPLACE FUNCTION nutrition.fn_meal_breakdown(p_user_id uuid, p_meal_id uuid)
RETURNS TABLE (
    meal_id uuid, logged_at timestamptz, local_date date, meal_type common.code, source common.code,
    version integer, hydration_credit boolean, editable boolean, totals jsonb, items jsonb,
    updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY SELECT * FROM nutrition.fn_meal_rows(p_user_id, ARRAY[p_meal_id]);
END
$$;

COMMENT ON FUNCTION nutrition.fn_meal_breakdown(uuid, uuid) IS 'One meal with items and 17-nutrient totals (STAR breakdown)';
REVOKE ALL ON FUNCTION nutrition.fn_meal_breakdown(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_meal_breakdown(uuid, uuid) TO app_rw, app_readonly;

-- Saved meals (templates) with their items.
CREATE OR REPLACE FUNCTION nutrition.fn_saved_meals(p_user_id uuid)
RETURNS TABLE (saved_meal_id uuid, name text, items jsonb, created_at timestamptz)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT
        s.id, s.name::text,
        coalesce(
            jsonb_agg(
                jsonb_build_object(
                    'food_id', i.food_id, 'food_name', f.name, 'quantity', i.quantity,
                    'unit_code', i.unit_code, 'unit_size', i.unit_size,
                    'available', f.status = 'active' AND f.deleted_at IS NULL
                )
                ORDER BY i.created_at, i.id
            ) FILTER (WHERE i.id IS NOT NULL),
            '[]'::jsonb
        ),
        s.created_at
    FROM nutrition.saved_meal AS s
    LEFT JOIN nutrition.saved_meal_item AS i ON i.saved_meal_id = s.id
    LEFT JOIN nutrition.food_item AS f ON f.id = i.food_id
    WHERE s.user_id = p_user_id AND s.deleted_at IS NULL
    GROUP BY s.id
    ORDER BY s.created_at DESC;
END
$$;

COMMENT ON FUNCTION nutrition.fn_saved_meals(uuid) IS 'Saved meal templates with items (max 50 per user)';
REVOKE ALL ON FUNCTION nutrition.fn_saved_meals(uuid) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_saved_meals(uuid) TO app_rw, app_readonly;
