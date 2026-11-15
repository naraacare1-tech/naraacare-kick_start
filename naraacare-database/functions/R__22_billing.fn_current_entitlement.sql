-- Effective tier for a user (doc 04 section 3): the highest of an active/in-grace store subscription and
-- an active entitlement grant; STANDARD when neither exists. The API calls it
-- on each request that needs the tier (no cache).
-- features = {feature_code: enabled}, limits = {feature_code: limit_value} for the effective tier.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

-- Internal (Session 14): the same rules without the actor check, for routines that already know whose
-- entitlement they need (the report worker in ops). Not SECURITY DEFINER and granted to no login role.
CREATE OR REPLACE FUNCTION billing.fn_entitlement_of(p_user_id uuid)
RETURNS TABLE (
    tier_code common.code,
    source common.code,
    expires_at timestamptz,
    features jsonb,
    limits jsonb
)
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_tier common.code := 'standard';
    v_source common.code := 'default';
    v_expires timestamptz;
BEGIN
    -- Candidates ranked: higher tier first, then store before grants, then the latest expiry.
    SELECT c.tier_code, c.source, c.expires_at
    INTO v_tier, v_source, v_expires
    FROM (
        SELECT p.tier_code, 'store'::text AS source, s.current_period_end AS expires_at
        FROM billing.subscription AS s
        INNER JOIN billing.store_product AS p ON p.platform = s.platform AND p.product_id = s.product_id
        WHERE s.user_id = p_user_id
          AND s.deleted_at IS NULL
          AND (
              -- Cancel = auto-renew off: access continues to the period end (doc 06 section 9).
              (s.status IN ('active', 'canceled') AND s.current_period_end > now())
              OR s.status = 'in_grace'
          )
        UNION ALL
        SELECT g.tier_code, g.source, g.ends_at
        FROM billing.entitlement_grant AS g
        WHERE g.user_id = p_user_id
          AND g.deleted_at IS NULL
          AND now() >= g.starts_at
          AND now() < g.ends_at
    ) AS c
    ORDER BY (c.tier_code = 'star') DESC, (c.source = 'store') DESC, c.expires_at DESC
    LIMIT 1;

    IF NOT FOUND THEN
        v_tier := 'standard';
        v_source := 'default';
        v_expires := NULL;
    END IF;

    RETURN QUERY
    SELECT
        v_tier,
        v_source,
        v_expires,
        coalesce(jsonb_object_agg(fe.feature_code, fe.enabled), '{}'::jsonb),
        coalesce(
            jsonb_object_agg(fe.feature_code, fe.limit_value) FILTER (WHERE fe.limit_value IS NOT NULL),
            '{}'::jsonb
        )
    FROM ref.feature_entitlement AS fe
    WHERE fe.tier_code = v_tier;
END
$$;

COMMENT ON FUNCTION billing.fn_entitlement_of(uuid) IS
'Internal: effective tier, features and limits of a user (callers check the actor themselves)';
REVOKE ALL ON FUNCTION billing.fn_entitlement_of(uuid) FROM public;

CREATE OR REPLACE FUNCTION billing.fn_current_entitlement(p_user_id uuid)
RETURNS TABLE (
    tier_code common.code,
    source common.code,
    expires_at timestamptz,
    features jsonb,
    limits jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY SELECT * FROM billing.fn_entitlement_of(p_user_id);
END
$$;

COMMENT ON FUNCTION billing.fn_current_entitlement(uuid) IS
'Effective tier (store subscription or grant), source, expiry, feature switches and limits';
REVOKE ALL ON FUNCTION billing.fn_current_entitlement(uuid) FROM public;
GRANT EXECUTE ON FUNCTION billing.fn_current_entitlement(uuid) TO app_rw, app_worker, app_readonly;
