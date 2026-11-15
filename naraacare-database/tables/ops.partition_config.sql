CREATE TABLE ops.partition_config (
    parent_table common.code PRIMARY KEY,
    bound_type common.code NOT NULL CHECK (bound_type IN ('timestamptz', 'date')),
    premake_months smallint NOT NULL DEFAULT 3 CHECK (premake_months BETWEEN 1 AND 12),
    retention_months smallint CHECK (retention_months > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ops.partition_config IS 'Monthly partitioned tables and how far ahead to create partitions';
