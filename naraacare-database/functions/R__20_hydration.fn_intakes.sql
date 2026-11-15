-- GET /hydration/intakes?date= and the intake representation for 201/200/409 responses (doc 04
-- section 2.5). Drinks of one local day in time order with the drink label and the edit flag (last
-- 2 within 7 days, OQ-53); with p_intake_id, that one drink whatever its day. Deleted rows never.
-- Errors: 42501 not the actor (-> 404).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION hydration.fn_intakes(p_user_id uuid, p_date date, p_intake_id uuid DEFAULT NULL)
RETURNS TABLE (
    intake_id uuid,
    logged_at timestamptz,
    local_date date,
    drink_code common.code,
    custom_drink_id uuid,
    label text,
    volume_ml integer,
    hydration_factor numeric,
    effective_ml numeric,
    source common.code,
    version integer,
    editable boolean
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
    WITH editable AS (SELECT e AS id FROM hydration.fn_editable_intake_ids(p_user_id) AS e)
    SELECT
        i.id, i.logged_at, i.local_date, i.drink_code, i.custom_drink_id,
        coalesce(t.label, c.name)::text, i.volume_ml, i.hydration_factor, i.effective_ml, i.source,
        i.version, i.id IN (SELECT e.id FROM editable AS e)
    FROM hydration.intake AS i
    LEFT JOIN ref.drink_type AS t ON t.code = i.drink_code
    LEFT JOIN hydration.custom_drink AS c ON c.id = i.custom_drink_id
    WHERE
        i.user_id = p_user_id AND i.deleted_at IS NULL
        AND (CASE WHEN p_intake_id IS NULL THEN i.local_date = p_date ELSE i.id = p_intake_id END)
    ORDER BY i.logged_at, i.id;
END
$$;

COMMENT ON FUNCTION hydration.fn_intakes(uuid, date, uuid) IS
'Drinks of a local day (or one drink by id) with label and editable flag';
REVOKE ALL ON FUNCTION hydration.fn_intakes(uuid, date, uuid) FROM public;
GRANT EXECUTE ON FUNCTION hydration.fn_intakes(uuid, date, uuid) TO app_rw;
