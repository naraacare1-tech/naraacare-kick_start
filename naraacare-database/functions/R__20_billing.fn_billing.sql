-- Billing reads (doc 04 section 2.12, Session 11).
--   * fn_plans: active store products (display prices are a fallback; the app shows the store's).
--   * fn_subscription: the caller's latest subscription (any status) for My Subscriptions.
--   * fn_billing_history: the caller's store transactions, newest first, keyset-paged.
-- Errors: 42501 not the actor (-> 404).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION billing.fn_plans()
RETURNS TABLE (
    platform common.code,
    product_id common.opaque_ref,
    tier_code common.code,
    period common.code,
    display_price_inr numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT p.platform, p.product_id, p.tier_code, p.period, p.display_price_inr
    FROM billing.store_product AS p
    WHERE p.active
    ORDER BY p.platform, p.period;
$$;

COMMENT ON FUNCTION billing.fn_plans() IS 'Active store products (display price fallback)';
REVOKE ALL ON FUNCTION billing.fn_plans() FROM public;
GRANT EXECUTE ON FUNCTION billing.fn_plans() TO app_rw;

CREATE OR REPLACE FUNCTION billing.fn_subscription(p_user_id uuid)
RETURNS TABLE (
    subscription_id uuid,
    platform common.code,
    product_id common.opaque_ref,
    period common.code,
    status common.code,
    auto_renew boolean,
    current_period_start timestamptz,
    current_period_end timestamptz,
    environment common.code
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
    SELECT
        s.id, s.platform, s.product_id, p.period, s.status, s.auto_renew, s.current_period_start,
        s.current_period_end, s.environment
    FROM billing.subscription AS s
    INNER JOIN billing.store_product AS p ON p.platform = s.platform AND p.product_id = s.product_id
    WHERE s.user_id = p_user_id AND s.deleted_at IS NULL
    ORDER BY s.current_period_end DESC
    LIMIT 1;
END
$$;

COMMENT ON FUNCTION billing.fn_subscription(uuid) IS 'The caller''s latest store subscription';
REVOKE ALL ON FUNCTION billing.fn_subscription(uuid) FROM public;
GRANT EXECUTE ON FUNCTION billing.fn_subscription(uuid) TO app_rw;

CREATE OR REPLACE FUNCTION billing.fn_billing_history(
    p_user_id uuid, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 20
)
RETURNS TABLE (
    transaction_id uuid,
    occurred_at timestamptz,
    product_id common.opaque_ref,
    platform common.code,
    type common.code,
    amount_micros bigint,
    currency common.currency
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
    SELECT t.id, t.occurred_at, s.product_id, s.platform, t.type, t.amount_micros, t.currency
    FROM billing.store_transaction AS t
    INNER JOIN billing.subscription AS s ON s.id = t.subscription_id
    WHERE s.user_id = p_user_id AND (p_before IS NULL OR t.occurred_at < p_before)
    ORDER BY t.occurred_at DESC, t.id DESC
    LIMIT least(greatest(coalesce(p_limit, 20), 1), 50);
END
$$;

COMMENT ON FUNCTION billing.fn_billing_history(uuid, timestamptz, integer) IS
'The caller''s store transactions, newest first (keyset paging by occurred_at)';
REVOKE ALL ON FUNCTION billing.fn_billing_history(uuid, timestamptz, integer) FROM public;
GRANT EXECUTE ON FUNCTION billing.fn_billing_history(uuid, timestamptz, integer) TO app_rw;
