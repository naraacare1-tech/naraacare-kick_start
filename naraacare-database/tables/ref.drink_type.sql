CREATE TABLE ref.drink_type (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    hydration_factor numeric(4, 3) NOT NULL CHECK (hydration_factor BETWEEN 0 AND 1),
    tier_required common.code NOT NULL REFERENCES ref.subscription_tier (code),
    is_alcohol boolean NOT NULL DEFAULT FALSE,
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.drink_type IS 'Drink hydration factors (doc 06 section 3.6) and tier (OQ-05)';
