CREATE TABLE ref.bmi_category (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    min_bmi numeric(4, 1) NOT NULL CHECK (min_bmi >= 0),
    max_bmi_exclusive numeric(4, 1) CHECK (max_bmi_exclusive > min_bmi),
    blocked_goal_codes common.code[] NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.bmi_category IS 'BMI guardrails: half-open ranges and blocked goals (doc 06 section 2.3)';
