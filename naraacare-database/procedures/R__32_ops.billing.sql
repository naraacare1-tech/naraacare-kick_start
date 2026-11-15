-- Billing worker routines (Session 11; doc 05 section 7 owner-run allow-list): they cross users, so they
-- are owned by migration_owner (table owner: RLS does not apply) and granted only to app_worker.
--   * ops.pr_tally_referrals(p_as_of): nightly (doc 06 section 6, OQ-39). For pending referrals:
--     active_days = distinct active days of the friend within 60 days of sign-up (max 60); qualified at
--     30 days if the friend's email is verified and onboarding is complete; disqualified when the 60
--     days pass first. Then each referrer with 5 qualified friends and no reward yet gets one STAR
--     grant: 50 days if they are STAR at that moment, else 30; a paying subscriber's grant starts at
--     the end of the paid period. One reward per referrer (unique constraint).
--   * ops.fn_subscriptions_to_reconcile(p_now, p_limit): active / in-grace / canceled subscriptions
--     ending within 24 h or not verified for 6 h, for the reconcile job (purchase token included).
CREATE OR REPLACE PROCEDURE ops.pr_tally_referrals(
    p_as_of timestamptz DEFAULT NULL,
    INOUT o_qualified integer DEFAULT NULL,
    INOUT o_rewarded integer DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_now timestamptz := coalesce(p_as_of, now());
    r record;
    v_star boolean;
    v_paid_end timestamptz;
    v_days integer;
    v_start timestamptz;
    v_grant uuid;
BEGIN
    UPDATE billing.referral AS f
    SET active_days = least(60, (
        SELECT count(DISTINCT d.local_date) FROM app.user_activity_day AS d
        WHERE d.user_id = f.referred_user_id
          AND d.local_date BETWEEN a.created_at::date AND (a.created_at + interval '60 days')::date
          AND (d.has_hydration OR d.has_nutrition OR d.has_sleep)
    ))
    FROM auth.user_account AS a
    WHERE a.id = f.referred_user_id AND f.status = 'pending';

    WITH q AS (
        UPDATE billing.referral AS f
        SET status = 'qualified', qualified_at = v_now
        FROM auth.user_account AS a
        INNER JOIN app.user_profile AS p ON p.user_id = a.id
        WHERE a.id = f.referred_user_id AND f.status = 'pending' AND f.active_days >= 30
          AND a.email_verified_at IS NOT NULL AND p.onboarding_completed_at IS NOT NULL
        RETURNING 1
    )
    SELECT count(*) INTO o_qualified FROM q;

    UPDATE billing.referral AS f
    SET status = 'disqualified', disqualify_reason = 'window_passed'
    FROM auth.user_account AS a
    WHERE a.id = f.referred_user_id AND f.status = 'pending' AND a.created_at + interval '60 days' < v_now;

    o_rewarded := 0;
    FOR r IN
        SELECT f.referrer_id FROM billing.referral AS f
        WHERE f.status = 'qualified'
          AND NOT EXISTS (SELECT 1 FROM billing.referral_reward AS w WHERE w.referrer_id = f.referrer_id)
        GROUP BY f.referrer_id
        HAVING count(*) >= 5
    LOOP
        SELECT max(s.current_period_end) INTO v_paid_end
        FROM billing.subscription AS s
        WHERE s.user_id = r.referrer_id AND s.deleted_at IS NULL
          AND s.status IN ('active', 'in_grace', 'canceled') AND s.current_period_end > v_now;
        v_star := v_paid_end IS NOT NULL OR EXISTS (
            SELECT 1 FROM billing.entitlement_grant AS g
            WHERE g.user_id = r.referrer_id AND g.deleted_at IS NULL AND g.tier_code = 'star'
              AND v_now >= g.starts_at AND v_now < g.ends_at
        );
        v_days := CASE WHEN v_star THEN 50 ELSE 30 END;
        v_start := greatest(v_now, coalesce(v_paid_end, v_now));
        INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
        VALUES (r.referrer_id, 'star', 'referral', v_start, v_start + make_interval(days => v_days))
        RETURNING id INTO v_grant;
        INSERT INTO billing.referral_reward (referrer_id, reward_days, grant_id)
        VALUES (r.referrer_id, v_days, v_grant);
        o_rewarded := o_rewarded + 1;
    END LOOP;
END
$$;

COMMENT ON PROCEDURE ops.pr_tally_referrals (timestamptz, integer, integer) IS
'Worker: update referral active days, qualify/disqualify friends and grant one-time referral rewards';
REVOKE ALL ON PROCEDURE ops.pr_tally_referrals(timestamptz, integer, integer) FROM public;
GRANT EXECUTE ON PROCEDURE ops.pr_tally_referrals(timestamptz, integer, integer) TO app_worker;

CREATE OR REPLACE FUNCTION ops.fn_subscriptions_to_reconcile(p_now timestamptz, p_limit integer DEFAULT 200)
RETURNS TABLE (
    subscription_id uuid,
    user_id uuid,
    platform text,
    product_id text,
    purchase_token text,
    original_transaction_id text,
    environment text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT
        s.id, s.user_id, s.platform::text, s.product_id::text, s.purchase_token::text,
        s.original_transaction_id::text, s.environment::text
    FROM billing.subscription AS s
    WHERE s.deleted_at IS NULL
      AND s.status IN ('active', 'in_grace', 'canceled', 'on_hold')
      AND (s.current_period_end < p_now + interval '24 hours' OR s.last_verified_at < p_now - interval '6 hours')
    ORDER BY s.last_verified_at
    LIMIT least(greatest(coalesce(p_limit, 200), 1), 1000);
$$;

COMMENT ON FUNCTION ops.fn_subscriptions_to_reconcile(timestamptz, integer) IS
'Worker: subscriptions to re-verify with the store (ending within 24 h or stale for 6 h)';
REVOKE ALL ON FUNCTION ops.fn_subscriptions_to_reconcile(timestamptz, integer) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_subscriptions_to_reconcile(timestamptz, integer) TO app_worker;
