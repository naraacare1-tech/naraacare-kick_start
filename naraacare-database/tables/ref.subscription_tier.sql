CREATE TABLE ref.subscription_tier (
    code common.code PRIMARY KEY CHECK (code IN ('standard', 'star')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.subscription_tier IS 'STANDARD (free) and STAR (paid) tiers';
