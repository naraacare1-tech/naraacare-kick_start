-- GET /foods/search (doc 04 section 2.4). Active foods whose name or alias (Hinglish/Hindi) matches
-- the query: prefix and substring matches first, then typo-tolerant trigram similarity (moong / mung),
-- each result with its default portion and the kcal of that portion. The query is matched as plain
-- text (LIKE wildcards escaped); barcode-only 'packaged' foods are not offered; the API validates it as SafeSearchQuery (1..64) first.
-- Served by ix_food_item__name_trgm and ix_food_alias__alias_trgm (GIN trigram).
-- Errors: 22023 (query empty or longer than 64 after trimming).
-- pg_trgm lives in schema public: its function and operator are schema-qualified.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_search_foods(p_query text, p_limit integer DEFAULT 25)
RETURNS TABLE (
    food_id uuid,
    name text,
    matched_alias text,
    category_code common.code,
    basis common.code,
    default_unit_code common.code,
    default_size common.code,
    default_portion_label text,
    default_quantity numeric,
    default_basis common.code,
    kcal_per_default numeric,
    score real
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_q text := lower(btrim(p_query));
    v_like text;
    v_limit integer := least(greatest(coalesce(p_limit, 25), 1), 25);
BEGIN
    IF v_q IS NULL OR char_length(v_q) NOT BETWEEN 1 AND 64 THEN
        RAISE EXCEPTION 'query must be 1..64 characters' USING ERRCODE = '22023', DETAIL = 'SEARCH_QUERY_INVALID';
    END IF;
    v_like := replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_');

    RETURN QUERY
    WITH name_hits AS (
        SELECT
            f.id, NULL::text AS alias,
            CASE
                WHEN f.name_normalized LIKE v_like || '%' THEN 3.0
                WHEN f.name_normalized LIKE '%' || v_like || '%' THEN 2.0
                ELSE 1.0
            END + public.similarity(f.name_normalized, v_q) AS s
        FROM nutrition.food_item AS f
        WHERE f.status = 'active' AND f.deleted_at IS NULL AND f.category_code <> 'packaged'
          AND (f.name_normalized LIKE '%' || v_like || '%' OR f.name_normalized OPERATOR(public.%) v_q)
    ),
    alias_hits AS (
        SELECT
            f.id, a.alias::text AS alias,
            CASE
                WHEN a.alias_normalized LIKE v_like || '%' THEN 3.0
                WHEN a.alias_normalized LIKE '%' || v_like || '%' THEN 2.0
                ELSE 1.0
            END + public.similarity(a.alias_normalized, v_q) - 0.01 AS s
        FROM nutrition.food_alias AS a
        INNER JOIN nutrition.food_item AS f ON f.id = a.food_id
        WHERE a.deleted_at IS NULL AND f.status = 'active' AND f.deleted_at IS NULL
          AND f.category_code <> 'packaged'
          AND (a.alias_normalized LIKE '%' || v_like || '%' OR a.alias_normalized OPERATOR(public.%) v_q)
    ),
    best AS (
        SELECT DISTINCT ON (h.id) h.id, h.alias, h.s
        FROM (SELECT * FROM name_hits UNION ALL SELECT * FROM alias_hits) AS h
        ORDER BY h.id, h.s DESC
    ),
    top AS (
        SELECT b.* FROM best AS b ORDER BY b.s DESC, b.id LIMIT v_limit
    ),
    defaults AS (
        SELECT DISTINCT ON (p.food_id) p.*
        FROM nutrition.fn_food_portions(ARRAY(SELECT t.id FROM top AS t)) AS p
        ORDER BY p.food_id, p.is_default DESC, p.quantity
    )
    SELECT
        f.id, f.name::text, t.alias, f.category_code, f.basis,
        d.unit_code, d.size, d.label, d.quantity, d.basis,
        round(
            f.calories_kcal * CASE
                WHEN d.basis = f.basis THEN d.quantity
                WHEN d.basis = 'ml' THEN d.quantity * f.density_g_per_ml
                ELSE d.quantity / f.density_g_per_ml
            END / 100,
            3
        ),
        t.s::real
    FROM top AS t
    INNER JOIN nutrition.food_item AS f ON f.id = t.id
    LEFT JOIN defaults AS d ON d.food_id = f.id
    ORDER BY t.s DESC, f.name;
END
$$;

COMMENT ON FUNCTION nutrition.fn_search_foods(text, integer) IS
'Food search by name or alias (prefix, substring, trigram) with the default portion and its kcal';
REVOKE ALL ON FUNCTION nutrition.fn_search_foods(text, integer) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_search_foods(text, integer) TO app_rw, app_readonly;
