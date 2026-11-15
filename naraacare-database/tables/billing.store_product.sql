CREATE TABLE billing.store_product (
    platform common.code NOT NULL CHECK (platform IN ('google_play', 'app_store')),
    product_id common.opaque_ref NOT NULL,
    tier_code common.code NOT NULL REFERENCES ref.subscription_tier (code),
    period common.code NOT NULL CHECK (period IN ('p1m', 'p1y')),
    display_price_inr numeric(8, 2) NOT NULL CHECK (display_price_inr > 0),
    active boolean NOT NULL DEFAULT TRUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (platform, product_id)
);
COMMENT ON TABLE billing.store_product IS 'Store products; prices shown in-app come from the store SDK (OQ-06)';
