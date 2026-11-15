-- GET /me and GET /me/onboarding (doc 04 section 2.2). One row: account, profile (NULL columns before
-- onboarding step 1), onboarding state, the streak counters and the Profile header counts (accepted
-- connections, active circles; Session 14). The streak cache reads as 0 once a day was missed.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- The result columns changed in Session 05 (age_recorded_on), which CREATE OR REPLACE cannot do.
DROP FUNCTION IF EXISTS app.fn_get_profile(uuid);

CREATE OR REPLACE FUNCTION app.fn_get_profile(p_user_id uuid)
RETURNS TABLE (
    user_id uuid,
    email common.email,
    status common.code,
    role common.code,
    full_name common.safe_text,
    username common.username,
    username_changed_at timestamptz,
    biological_sex common.code,
    avatar_code common.code,
    age_years smallint,
    age_recorded_on date,
    height_cm numeric,
    weight_kg numeric,
    target_weight_kg numeric,
    weight_goal_code common.code,
    activity_level_code common.code,
    body_type_code common.code,
    medical_conditions common.code[],
    height_unit common.code,
    weight_unit common.code,
    temperature_unit common.code,
    timezone common.iana_timezone,
    locale common.locale,
    sleep_start_local time,
    wake_local time,
    sleep_goal_min smallint,
    biometric_lock boolean,
    onboarding_step smallint,
    onboarding_completed_at timestamptz,
    current_streak integer,
    longest_streak integer,
    connections_count integer,
    circles_count integer,
    profile_updated_at timestamptz,
    member_since date
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT
        a.id, a.email, a.status, a.role,
        p.full_name, p.username, p.username_changed_at, p.biological_sex, p.avatar_code,
        p.age_years, p.age_recorded_on, p.height_cm, p.weight_kg, p.target_weight_kg,
        p.weight_goal_code, p.activity_level_code, p.body_type_code, p.medical_conditions,
        coalesce(p.height_unit, 'cm')::common.code, coalesce(p.weight_unit, 'kg')::common.code,
        coalesce(p.temperature_unit, 'c')::common.code,
        coalesce(p.timezone, 'Asia/Kolkata')::common.iana_timezone, coalesce(p.locale, 'en')::common.locale,
        coalesce(p.sleep_start_local, time '23:00'), coalesce(p.wake_local, time '07:00'),
        p.sleep_goal_min, coalesce(p.biometric_lock, FALSE),
        coalesce(p.onboarding_step, 0::smallint), p.onboarding_completed_at,
        CASE
            WHEN s.last_active_date >= common.fn_local_date(coalesce(p.timezone, 'Asia/Kolkata')) - 1
                THEN s.current_streak
            ELSE 0
        END,
        coalesce(s.longest_streak, 0),
        (
            SELECT count(*)::integer FROM social.connection AS c
            WHERE p_user_id IN (c.requester_id, c.addressee_id)
              AND c.status = 'accepted' AND c.deleted_at IS NULL
        ),
        (
            SELECT count(*)::integer FROM social.circle_member AS m
            INNER JOIN social.care_circle AS cc ON cc.id = m.circle_id AND cc.deleted_at IS NULL
            WHERE m.user_id = p_user_id AND m.status = 'active'
        ),
        p.updated_at,
        (a.created_at AT TIME ZONE coalesce(p.timezone, 'Asia/Kolkata'))::date
    FROM auth.user_account AS a
    LEFT JOIN app.user_profile AS p ON p.user_id = a.id AND p.deleted_at IS NULL
    LEFT JOIN app.user_streak AS s ON s.user_id = a.id
    WHERE a.id = p_user_id
      AND a.status <> 'deleted';
END
$$;

COMMENT ON FUNCTION app.fn_get_profile(uuid) IS 'Account + profile + onboarding state + streak for GET /me';
REVOKE ALL ON FUNCTION app.fn_get_profile(uuid) FROM public;
GRANT EXECUTE ON FUNCTION app.fn_get_profile(uuid) TO app_rw, app_worker, app_readonly;
