-- POST /nutrition/voice/parse (doc 04 section 2.4, OQ-43): best food for each phrase the API cut out
-- of a transcript ("roti", "dal", "chawal"). Exact name/alias first (score 1), then the best of
-- trigram similarity and word similarity (the phrase as a word inside a longer name: "roti" in
-- "Roti (Whole Wheat)"), at least 0.35; ties go to the shorter name. Phrases without a match return
-- food_id NULL (shown as "unmatched").
-- p_phrases: 1..20 lower-case phrases of 1..60 characters; the API has validated the transcript
-- (SafeText(300)) and never sends it whole. Errors: 22023 VOICE_PHRASES_INVALID.
-- pg_trgm lives in schema public: its function and operator are schema-qualified.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION nutrition.fn_alias_match(p_phrases text[])
RETURNS TABLE (
    phrase_no integer,
    phrase text,
    food_id uuid,
    name text,
    category_code common.code,
    score real
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
BEGIN
    IF p_phrases IS NULL OR cardinality(p_phrases) NOT BETWEEN 1 AND 20
       OR EXISTS (SELECT 1 FROM unnest(p_phrases) AS x (v) WHERE x.v IS NULL OR char_length(x.v) NOT BETWEEN 1 AND 60)
    THEN
        RAISE EXCEPTION 'phrases must be 1..20 strings of 1..60 characters'
            USING ERRCODE = '22023', DETAIL = 'VOICE_PHRASES_INVALID';
    END IF;

    RETURN QUERY
    WITH phrases AS (
        SELECT x.ord::integer AS phrase_no, lower(btrim(x.v)) AS phrase
        FROM unnest(p_phrases) WITH ORDINALITY AS x (v, ord)
    ),
    candidates AS (
        SELECT f.id, f.name::text AS name, f.category_code, f.name_normalized AS term
        FROM nutrition.food_item AS f
        WHERE f.status = 'active' AND f.deleted_at IS NULL AND f.category_code <> 'packaged'
        UNION ALL
        SELECT f.id, f.name::text, f.category_code, a.alias_normalized
        FROM nutrition.food_alias AS a
        INNER JOIN nutrition.food_item AS f ON f.id = a.food_id
        WHERE a.deleted_at IS NULL AND f.status = 'active' AND f.deleted_at IS NULL
          AND f.category_code <> 'packaged'
    )
    SELECT p.phrase_no, p.phrase, m.id, m.name, m.category_code, m.s
    FROM phrases AS p
    LEFT JOIN LATERAL (
        SELECT
            c.id, c.name, c.category_code,
            CASE
                WHEN c.term = p.phrase THEN 1.0
                ELSE greatest(public.similarity(c.term, p.phrase), 0.95 * public.word_similarity(p.phrase, c.term))
            END::real AS s
        FROM candidates AS c
        WHERE c.term = p.phrase OR c.term OPERATOR(public.%) p.phrase OR p.phrase OPERATOR(public.<%) c.term
        ORDER BY
            (c.term = p.phrase) DESC,
            greatest(public.similarity(c.term, p.phrase), 0.95 * public.word_similarity(p.phrase, c.term)) DESC,
            char_length(c.term), c.id
        LIMIT 1
    ) AS m ON m.s >= 0.35
    ORDER BY p.phrase_no;
END
$$;

COMMENT ON FUNCTION nutrition.fn_alias_match(text[]) IS
'Voice parsing: best active food per phrase by exact name/alias, else trigram similarity >= 0.35';
REVOKE ALL ON FUNCTION nutrition.fn_alias_match(text[]) FROM public;
GRANT EXECUTE ON FUNCTION nutrition.fn_alias_match(text[]) TO app_rw;
