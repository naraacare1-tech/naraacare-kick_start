CREATE TABLE ref.calc_version (
    code common.version_label PRIMARY KEY,
    effective_from date NOT NULL,
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 500),
    approved_by common.safe_text CHECK (char_length(approved_by) BETWEEN 1 AND 100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.calc_version IS 'Version of calculation constants; snapshots record the version they used';
