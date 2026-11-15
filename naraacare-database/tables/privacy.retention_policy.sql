CREATE TABLE privacy.retention_policy (
    table_name common.code PRIMARY KEY,
    retention_days integer NOT NULL CHECK (retention_days > 0),
    action common.code NOT NULL CHECK (action IN ('purge', 'anonymize')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privacy.retention_policy IS 'Per-table retention (doc 05 section 9, pending legal approval OQ-48)';
