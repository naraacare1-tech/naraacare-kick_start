-- POST /me/onboarding/complete (doc 04 section 2.2). Requires all 6 steps saved. In one transaction:
-- records the consents, stores today's target snapshot (computed by the API from the saved answers),
-- sets the default sleep goal for the user's age and marks onboarding complete.
-- p_consents = [{"purpose": code, "policy_version": label, "granted": bool}, ...]; health_data must be
-- granted (doc 07 SEC-7.1: required to use tracking).
-- Errors: P0001 ONBOARDING_INCOMPLETE / ONBOARDING_ALREADY_COMPLETED / CONSENT_REQUIRED,
--         22023 INVALID_CONSENTS (plus the errors of the procedures it calls).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE app.pr_complete_onboarding(
    p_user_id uuid,
    p_snapshot jsonb,
    p_consents jsonb,
    p_app_version common.app_version DEFAULT NULL,
    p_ip inet DEFAULT NULL,
    INOUT o_effective_date date DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_profile app.user_profile%ROWTYPE;
    v_consent jsonb;
    v_consent_id bigint;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT * INTO v_profile FROM app.user_profile WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND OR v_profile.onboarding_step < 6 THEN
        RAISE EXCEPTION 'onboarding steps are incomplete' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_INCOMPLETE';
    END IF;
    IF v_profile.onboarding_completed_at IS NOT NULL THEN
        RAISE EXCEPTION 'onboarding already completed' USING ERRCODE = 'P0001', DETAIL = 'ONBOARDING_ALREADY_COMPLETED';
    END IF;

    IF p_consents IS NULL OR jsonb_typeof(p_consents) <> 'array' OR jsonb_array_length(p_consents) > 10
       OR EXISTS (
           SELECT 1 FROM jsonb_array_elements(p_consents) AS c (v)
           WHERE jsonb_typeof(c.v) <> 'object'
              OR jsonb_typeof(c.v -> 'granted') IS DISTINCT FROM 'boolean'
              OR jsonb_typeof(c.v -> 'purpose') IS DISTINCT FROM 'string'
              OR jsonb_typeof(c.v -> 'policy_version') IS DISTINCT FROM 'string'
       ) THEN
        RAISE EXCEPTION 'consents must be a list of {purpose, policy_version, granted}'
            USING ERRCODE = '22023', DETAIL = 'INVALID_CONSENTS';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM jsonb_array_elements(p_consents) AS c (v)
        WHERE c.v ->> 'purpose' = 'health_data' AND (c.v -> 'granted')::boolean
    ) THEN
        RAISE EXCEPTION 'health data consent is required' USING ERRCODE = 'P0001', DETAIL = 'CONSENT_REQUIRED';
    END IF;

    FOR v_consent IN SELECT c.v FROM jsonb_array_elements(p_consents) AS c (v) LOOP
        v_consent_id := NULL;
        CALL privacy.pr_record_consent(
            p_user_id,
            (v_consent ->> 'purpose')::common.code,
            (v_consent ->> 'policy_version')::common.version_label,
            (v_consent -> 'granted')::boolean,
            p_app_version,
            p_ip,
            v_consent_id
        );
    END LOOP;

    o_effective_date := common.fn_local_date(v_profile.timezone);
    CALL app.pr_upsert_target_snapshot(p_user_id, o_effective_date, p_snapshot);

    UPDATE app.user_profile AS p
    SET onboarding_completed_at = now(),
        sleep_goal_min = coalesce(p.sleep_goal_min, (
            SELECT g.goal_min FROM ref.sleep_goal_by_age AS g
            WHERE p.age_years BETWEEN g.min_age AND g.max_age
        ))
    WHERE p.user_id = p_user_id;
END
$$;

COMMENT ON PROCEDURE app.pr_complete_onboarding (uuid, jsonb, jsonb, common.app_version, inet, date) IS
'Finish onboarding: consents (health_data required), today''s target snapshot, default sleep goal';
REVOKE ALL ON PROCEDURE app.pr_complete_onboarding(uuid, jsonb, jsonb, common.app_version, inet, date)
FROM public;
GRANT EXECUTE ON PROCEDURE app.pr_complete_onboarding(uuid, jsonb, jsonb, common.app_version, inet, date)
TO app_rw;
