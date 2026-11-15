-- Reference payload for GET /reference/bootstrap (doc 04 section 2.3): one JSON document plus an ETag
-- (SHA-256 of the document). Public and identical for every user, so the API serves it with
-- Cache-Control max-age=3600 and answers 304 on a matching If-None-Match: the DB is hit about once an
-- hour per API task, not once per app launch. Only display/calculation data, never user data.
-- Report sections, suggested Rin prompts and the minimum app version are added in their sessions.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION ref.fn_bootstrap()
RETURNS TABLE (etag text, payload jsonb)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_payload jsonb;
BEGIN
    SELECT jsonb_build_object(
        'calc_version', (SELECT max(code) FROM ref.calc_version WHERE effective_from <= current_date),
        'activity_levels', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'onboarding_label', onboarding_label
            ) ORDER BY display_order, code), '[]')
            FROM ref.activity_level
        ),
        'body_types', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) ORDER BY display_order, code), '[]')
            FROM ref.body_type
        ),
        'weight_goals', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'direction', direction, 'kg_per_week', kg_per_week
            ) ORDER BY display_order, code), '[]')
            FROM ref.weight_goal
            WHERE offered
        ),
        'bmi_categories', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'min_bmi', min_bmi, 'max_bmi_exclusive', max_bmi_exclusive,
                'blocked_goal_codes', to_jsonb(blocked_goal_codes)
            ) ORDER BY min_bmi), '[]')
            FROM ref.bmi_category
        ),
        'drinks', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'hydration_factor', hydration_factor,
                'tier_required', tier_required, 'is_alcohol', is_alcohol
            ) ORDER BY display_order, code), '[]')
            FROM ref.drink_type
        ),
        'workouts', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) ORDER BY display_order, code), '[]')
            FROM ref.workout_type
        ),
        'nutrients', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'unit', unit, 'tier_required', tier_required
            ) ORDER BY display_order, code), '[]')
            FROM ref.nutrient
        ),
        'units', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) ORDER BY code), '[]')
            FROM ref.unit
        ),
        'food_categories', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', fc.code,
                'label', fc.label,
                'portions', (
                    SELECT coalesce(jsonb_agg(jsonb_build_object(
                        'unit_code', u.unit_code, 'size', u.size, 'quantity', u.quantity,
                        'basis', u.basis, 'is_default', u.is_default
                    ) ORDER BY u.unit_code, u.size), '[]')
                    FROM ref.food_category_unit AS u
                    WHERE u.category_code = fc.code
                )
            ) ORDER BY fc.code), '[]')
            FROM ref.food_category AS fc
        ),
        'medical_conditions', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'kind', kind
            ) ORDER BY display_order, code), '[]')
            FROM ref.medical_condition
        ),
        'avatars', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'sex', sex, 'body_type_code', body_type_code, 'asset_key', asset_key
            ) ORDER BY code), '[]')
            FROM ref.avatar
        ),
        'wallpapers', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'code', code, 'label', label, 'asset_key', asset_key
            ) ORDER BY code), '[]')
            FROM ref.wallpaper
        ),
        'sleep_goals', (
            SELECT coalesce(jsonb_agg(jsonb_build_object(
                'min_age', min_age, 'max_age', max_age, 'goal_min', goal_min
            ) ORDER BY min_age), '[]')
            FROM ref.sleep_goal_by_age
        ),
        'tiers', (
            SELECT coalesce(jsonb_agg(jsonb_build_object('code', code, 'label', label) ORDER BY display_order), '[]')
            FROM ref.subscription_tier
        )
    ) INTO v_payload;

    RETURN QUERY SELECT encode(sha256(convert_to(v_payload::text, 'UTF8')), 'hex'), v_payload;
END
$$;

COMMENT ON FUNCTION ref.fn_bootstrap() IS 'Public reference payload + ETag (SHA-256) for GET /reference/bootstrap';
REVOKE ALL ON FUNCTION ref.fn_bootstrap() FROM public;
GRANT EXECUTE ON FUNCTION ref.fn_bootstrap() TO app_rw, app_worker, app_readonly;
