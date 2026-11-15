-- PUT /me/settings (doc 04 section 2.2): display units, timezone, locale, sleep window, biometric lock.
-- All values are required (PUT). The timezone must be a real IANA zone known to the server
-- (pg_timezone_names), not just well-formed, because "today" for every summary is computed in it.
-- Creates the profile row if onboarding has not started yet.
-- Errors: 22023 INVALID_TIMEZONE / SETTINGS_REQUIRED; table CHECKs for units and the sleep window.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_update_settings(
    p_user_id uuid,
    p_height_unit common.code,
    p_weight_unit common.code,
    p_temperature_unit common.code,
    p_timezone common.iana_timezone,
    p_locale common.locale,
    p_sleep_start_local time,
    p_wake_local time,
    p_biometric_lock boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_height_unit IS NULL OR p_weight_unit IS NULL OR p_temperature_unit IS NULL OR p_timezone IS NULL
       OR p_locale IS NULL OR p_sleep_start_local IS NULL OR p_wake_local IS NULL OR p_biometric_lock IS NULL THEN
        RAISE EXCEPTION 'all settings are required' USING ERRCODE = '22023', DETAIL = 'SETTINGS_REQUIRED';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names AS tz WHERE tz.name = p_timezone) THEN
        RAISE EXCEPTION 'unknown timezone' USING ERRCODE = '22023', DETAIL = 'INVALID_TIMEZONE';
    END IF;

    INSERT INTO app.user_profile (
        user_id, height_unit, weight_unit, temperature_unit, timezone, locale,
        sleep_start_local, wake_local, biometric_lock
    ) VALUES (
        p_user_id, p_height_unit, p_weight_unit, p_temperature_unit, p_timezone, p_locale,
        p_sleep_start_local, p_wake_local, p_biometric_lock
    )
    ON CONFLICT (user_id) DO UPDATE SET
        height_unit = excluded.height_unit,
        weight_unit = excluded.weight_unit,
        temperature_unit = excluded.temperature_unit,
        timezone = excluded.timezone,
        locale = excluded.locale,
        sleep_start_local = excluded.sleep_start_local,
        wake_local = excluded.wake_local,
        biometric_lock = excluded.biometric_lock;
END
$$;

COMMENT ON PROCEDURE app.pr_update_settings (
    uuid, common.code, common.code, common.code, common.iana_timezone, common.locale, time, time, boolean
) IS 'Replace display settings (units, timezone, locale, sleep window, biometric lock)';
REVOKE ALL ON PROCEDURE app.pr_update_settings(
    uuid, common.code, common.code, common.code, common.iana_timezone, common.locale, time, time, boolean
) FROM public;
GRANT EXECUTE ON PROCEDURE app.pr_update_settings(
    uuid, common.code, common.code, common.code, common.iana_timezone, common.locale, time, time, boolean
) TO app_rw;
