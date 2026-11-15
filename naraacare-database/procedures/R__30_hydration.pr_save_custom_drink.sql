-- POST /hydration/custom-drinks (doc 04 section 2.5, doc 06 section 3.6). STAR (custom_drinks). The
-- user confirms the factor (AI estimate, 0.85 default, or their own) and the drink is saved for reuse.
--   * Name: fn_validate_text (no markup/scripts, rejected, never stripped), outer spaces trimmed,
--     1..60 characters, unique per user ignoring case (ALREADY_EXISTS; a partial unique index enforces it too).
--   * Factor 0..1 with 3 decimals; estimated_by ai | default | user.
--   * At most 100 custom drinks per user (CUSTOM_DRINK_LIMIT).
-- Errors: 42501 not the actor, 22023 invalid, P0001 UPGRADE_REQUIRED / ALREADY_EXISTS / CUSTOM_DRINK_LIMIT.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE hydration.pr_save_custom_drink(
    p_user_id uuid,
    p_name text,
    p_hydration_factor numeric,
    p_estimated_by common.code,
    INOUT o_custom_drink_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_name common.safe_text;
    v_features jsonb;
    v_count integer;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_name := btrim(common.fn_validate_text(p_name, 60));
    IF v_name IS NULL OR char_length(v_name) < 1 THEN
        RAISE EXCEPTION 'name is required' USING ERRCODE = '22023', DETAIL = 'NAME_INVALID';
    END IF;
    IF p_hydration_factor IS NULL OR p_hydration_factor NOT BETWEEN 0 AND 1
       OR p_hydration_factor <> round(p_hydration_factor, 3) THEN
        RAISE EXCEPTION 'factor must be 0..1 (3 decimals)' USING ERRCODE = '22023', DETAIL = 'FACTOR_INVALID';
    END IF;
    IF p_estimated_by IS NULL OR p_estimated_by NOT IN ('ai', 'default', 'user') THEN
        RAISE EXCEPTION 'unknown estimate source' USING ERRCODE = '22023', DETAIL = 'FACTOR_INVALID';
    END IF;
    SELECT e.features INTO v_features FROM billing.fn_current_entitlement(p_user_id) AS e;
    IF NOT coalesce((v_features ->> 'custom_drinks')::boolean, FALSE) THEN
        RAISE EXCEPTION 'custom drinks need STAR' USING ERRCODE = 'P0001', DETAIL = 'UPGRADE_REQUIRED';
    END IF;

    -- Serialise this user's custom-drink writes so the count and name checks cannot race.
    PERFORM 1 FROM app.user_profile AS p WHERE p.user_id = p_user_id FOR UPDATE;
    IF EXISTS (
        SELECT 1 FROM hydration.custom_drink AS c
        WHERE c.user_id = p_user_id AND c.deleted_at IS NULL AND lower(c.name::text) = lower(v_name::text)
    ) THEN
        RAISE EXCEPTION 'a custom drink with this name exists' USING ERRCODE = 'P0001', DETAIL = 'ALREADY_EXISTS';
    END IF;
    SELECT count(*) INTO v_count
    FROM hydration.custom_drink AS c WHERE c.user_id = p_user_id AND c.deleted_at IS NULL;
    IF v_count >= 100 THEN
        RAISE EXCEPTION 'at most 100 custom drinks' USING ERRCODE = 'P0001', DETAIL = 'CUSTOM_DRINK_LIMIT';
    END IF;

    INSERT INTO hydration.custom_drink (user_id, name, hydration_factor, estimated_by, created_by, updated_by)
    VALUES (p_user_id, v_name, p_hydration_factor, p_estimated_by, p_user_id, p_user_id)
    RETURNING id INTO o_custom_drink_id;
END
$$;

COMMENT ON PROCEDURE hydration.pr_save_custom_drink (uuid, text, numeric, common.code, uuid) IS
'STAR: save a confirmed custom drink (unique name per user, at most 100)';
REVOKE ALL ON PROCEDURE hydration.pr_save_custom_drink(uuid, text, numeric, common.code, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE hydration.pr_save_custom_drink(uuid, text, numeric, common.code, uuid) TO app_rw;
