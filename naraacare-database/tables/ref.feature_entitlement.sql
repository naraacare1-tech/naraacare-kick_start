CREATE TABLE ref.feature_entitlement (
    tier_code common.code NOT NULL REFERENCES ref.subscription_tier (code),
    feature_code common.code NOT NULL,
    enabled boolean NOT NULL,
    limit_value integer CHECK (limit_value >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tier_code, feature_code)
);
COMMENT ON TABLE ref.feature_entitlement IS 'Server-side tier matrix (doc 04 section 3); limit_value e.g. meal logs per day';
