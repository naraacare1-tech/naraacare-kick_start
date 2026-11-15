CREATE TABLE ref.nutrient (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    unit common.code NOT NULL CHECK (unit IN ('kcal', 'g', 'mg', 'mcg')),
    tier_required common.code NOT NULL REFERENCES ref.subscription_tier (code),
    display_order smallint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.nutrient IS 'The 17 tracked nutrients; STANDARD sees 6 (doc 01 section 4)';
