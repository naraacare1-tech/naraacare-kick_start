CREATE TABLE ref.feature_flag (
    key common.code PRIMARY KEY,
    enabled boolean NOT NULL,
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 200),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.feature_flag IS 'Server-side feature flags';
