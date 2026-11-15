CREATE TABLE ref.body_type (
    code common.code PRIMARY KEY CHECK (code IN ('ectomorph', 'mesomorph', 'endomorph')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    lbw_factor numeric(4, 3) NOT NULL CHECK (lbw_factor BETWEEN 0.8 AND 1.2),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.body_type IS 'Lean-body-weight factor per body type (doc 06 section 3.2, product choice)';
