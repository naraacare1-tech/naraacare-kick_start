-- GET /hydration/drinks (doc 04 section 2.5, OQ-05): the standard drinks with their factor and a
-- `locked` flag for the caller's tier (STAR drinks need premium_drinks), then the caller's own
-- custom drinks (locked unless custom_drinks is enabled: kept after a downgrade, doc 06 section 9).
-- Errors: 42501 not the actor (-> 404).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION hydration.fn_drinks_for_user(p_user_id uuid)
RETURNS TABLE (
    kind text,
    drink_code common.code,
    custom_drink_id uuid,
    label text,
    hydration_factor numeric,
    tier_required common.code,
    is_alcohol boolean,
    locked boolean,
    display_order integer
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
#variable_conflict use_column
DECLARE
    v_features jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    RETURN QUERY
    SELECT
        'standard'::text, t.code, NULL::uuid, t.label::text, t.hydration_factor, t.tier_required,
        t.is_alcohol,
        t.tier_required <> 'standard' AND NOT coalesce((v_features ->> 'premium_drinks')::boolean, FALSE),
        t.display_order::integer
    FROM ref.drink_type AS t
    UNION ALL
    SELECT
        'custom'::text, NULL::common.code, c.id, c.name::text, c.hydration_factor, 'star'::common.code,
        FALSE, NOT coalesce((v_features ->> 'custom_drinks')::boolean, FALSE),
        (1000 + row_number() OVER (ORDER BY lower(c.name::text)))::integer
    FROM hydration.custom_drink AS c
    WHERE c.user_id = p_user_id AND c.deleted_at IS NULL
    ORDER BY 9;
END
$$;

COMMENT ON FUNCTION hydration.fn_drinks_for_user(uuid) IS
'Standard drinks with tier lock flags, then the caller''s custom drinks';
REVOKE ALL ON FUNCTION hydration.fn_drinks_for_user(uuid) FROM public;
GRANT EXECUTE ON FUNCTION hydration.fn_drinks_for_user(uuid) TO app_rw;
