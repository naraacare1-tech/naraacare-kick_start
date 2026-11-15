CREATE TABLE ref.activity_level (
    code common.code PRIMARY KEY
    CHECK (code IN ('sedentary', 'lightly_active', 'moderately_active', 'very_active')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    onboarding_label common.safe_text NOT NULL CHECK (char_length(onboarding_label) BETWEEN 1 AND 80),
    tdee_multiplier numeric(4, 3) NOT NULL CHECK (tdee_multiplier > 0 AND tdee_multiplier <= 2.5),
    hydration_activity_code common.code NOT NULL REFERENCES ref.hydration_activity (code),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.activity_level IS 'Onboarding activity answer to TDEE multiplier and hydration activity (OQ-12, OQ-13)';
