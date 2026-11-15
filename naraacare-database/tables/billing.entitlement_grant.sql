CREATE TABLE billing.entitlement_grant (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    tier_code common.code NOT NULL REFERENCES ref.subscription_tier (code),
    source common.code NOT NULL CHECK (source IN ('referral', 'promo', 'support')),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CHECK (ends_at > starts_at)
);
COMMENT ON TABLE billing.entitlement_grant IS 'Server-side STAR grants (referral rewards, promos, support)';
