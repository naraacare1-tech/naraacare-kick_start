-- PUT /hydration/intakes/{id} and DELETE /hydration/intakes/{id} (doc 04 section 2.5). Optimistic
-- concurrency with the version the client last saw (If-Match); only the last 2 drinks within 7 days
-- may change (OQ-53). An edit may change the volume (1..3000; a swipe-down entry may keep -100) and
-- the drink (same tier checks as logging; the factor is re-snapshotted only when the drink changes).
-- The day's summary row is locked first; the day's water volume can never go below 0.
-- Errors: 42501 not found / not the actor's (-> 404), P0001 VERSION_CONFLICT / EDIT_WINDOW_CLOSED /
--         UPGRADE_REQUIRED / WATER_BELOW_ZERO, 22023 invalid volume or drink.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal: find, lock and check the drink the caller may change.
CREATE OR REPLACE FUNCTION hydration.fn_lock_editable_intake(
    p_user_id uuid, p_intake_id uuid, p_expected_version integer
)
RETURNS hydration.intake
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row hydration.intake%ROWTYPE;
BEGIN
    SELECT * INTO v_row FROM hydration.intake AS i
    WHERE i.id = p_intake_id AND i.user_id = p_user_id AND i.deleted_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'drink not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;
    CALL hydration.pr_lock_daily_summary(p_user_id, v_row.local_date);
    SELECT * INTO v_row FROM hydration.intake AS i
    WHERE i.id = p_intake_id AND i.logged_at = v_row.logged_at AND i.deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'drink not found' USING ERRCODE = '42501', DETAIL = 'NOT_FOUND';
    END IF;
    IF p_expected_version IS DISTINCT FROM v_row.version THEN
        RAISE EXCEPTION 'drink was changed elsewhere' USING ERRCODE = 'P0001', DETAIL = 'VERSION_CONFLICT';
    END IF;
    IF p_intake_id NOT IN (SELECT e FROM hydration.fn_editable_intake_ids(p_user_id) AS e) THEN
        RAISE EXCEPTION 'only the last 2 drinks within 7 days can change'
            USING ERRCODE = 'P0001', DETAIL = 'EDIT_WINDOW_CLOSED';
    END IF;
    RETURN v_row;
END
$$;

COMMENT ON FUNCTION hydration.fn_lock_editable_intake(uuid, uuid, integer) IS
'Internal: lock a drink the caller may edit (exists, version matches, last 2 within 7 days)';
REVOKE ALL ON FUNCTION hydration.fn_lock_editable_intake(uuid, uuid, integer) FROM public;

CREATE OR REPLACE PROCEDURE hydration.pr_update_intake(
    p_user_id uuid,
    p_intake_id uuid,
    p_expected_version integer,
    p_volume_ml integer,
    p_drink_code common.code,
    p_custom_drink_id uuid,
    INOUT o_version integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row hydration.intake%ROWTYPE;
    v_drink common.code;
    v_custom uuid;
    v_volume integer;
    v_factor numeric(4, 3);
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF num_nonnulls(p_drink_code, p_custom_drink_id) > 1 THEN
        RAISE EXCEPTION 'one drink only' USING ERRCODE = '22023', DETAIL = 'INTAKE_INVALID';
    END IF;
    v_row := hydration.fn_lock_editable_intake(p_user_id, p_intake_id, p_expected_version);

    v_volume := coalesce(p_volume_ml, v_row.volume_ml);
    IF p_drink_code IS NULL AND p_custom_drink_id IS NULL THEN
        v_drink := v_row.drink_code;
        v_custom := v_row.custom_drink_id;
    ELSE
        v_drink := p_drink_code;
        v_custom := p_custom_drink_id;
    END IF;
    IF NOT (v_volume BETWEEN 1 AND 3000
            OR (v_volume = -100 AND v_row.source = 'swipe' AND v_drink = 'water')) THEN
        RAISE EXCEPTION 'volume must be 1..3000 mL' USING ERRCODE = '22023', DETAIL = 'VOLUME_INVALID';
    END IF;

    v_factor := v_row.hydration_factor;
    IF v_drink IS DISTINCT FROM v_row.drink_code OR v_custom IS DISTINCT FROM v_row.custom_drink_id THEN
        v_factor := hydration.fn_usable_drink_factor(p_user_id, v_drink, v_custom);
    END IF;

    UPDATE hydration.intake AS i
    SET drink_code = v_drink, custom_drink_id = v_custom, volume_ml = v_volume, hydration_factor = v_factor,
        effective_ml = round(v_volume * v_factor, 1), version = i.version + 1, updated_by = p_user_id,
        updated_at = now()
    WHERE i.id = p_intake_id AND i.logged_at = v_row.logged_at
    RETURNING i.version INTO o_version;

    CALL hydration.pr_refresh_daily_summary(p_user_id, v_row.local_date);
END
$$;

COMMENT ON PROCEDURE hydration.pr_update_intake (uuid, uuid, integer, integer, common.code, uuid, integer) IS
'Edit one of the last 2 drinks (If-Match version): volume and/or drink, factor re-snapshotted';
REVOKE ALL ON PROCEDURE hydration.pr_update_intake(uuid, uuid, integer, integer, common.code, uuid, integer)
FROM public;
GRANT EXECUTE ON PROCEDURE hydration.pr_update_intake(uuid, uuid, integer, integer, common.code, uuid, integer)
TO app_rw;

CREATE OR REPLACE PROCEDURE hydration.pr_delete_intake(
    p_user_id uuid,
    p_intake_id uuid,
    p_expected_version integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_row hydration.intake%ROWTYPE;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    v_row := hydration.fn_lock_editable_intake(p_user_id, p_intake_id, p_expected_version);
    UPDATE hydration.intake AS i
    SET deleted_at = now(), version = i.version + 1, updated_by = p_user_id, updated_at = now()
    WHERE i.id = p_intake_id AND i.logged_at = v_row.logged_at;
    CALL hydration.pr_refresh_daily_summary(p_user_id, v_row.local_date);
END
$$;

COMMENT ON PROCEDURE hydration.pr_delete_intake (uuid, uuid, integer) IS
'Soft-delete one of the last 2 drinks (If-Match version); the day water must stay >= 0';
REVOKE ALL ON PROCEDURE hydration.pr_delete_intake(uuid, uuid, integer) FROM public;
GRANT EXECUTE ON PROCEDURE hydration.pr_delete_intake(uuid, uuid, integer) TO app_rw;
