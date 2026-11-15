CREATE TABLE audit.change_log (
    id bigint GENERATED ALWAYS AS IDENTITY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    schema_name common.code NOT NULL,
    table_name common.code NOT NULL,
    row_pk common.opaque_ref NOT NULL,
    action common.code NOT NULL CHECK (action IN ('insert', 'update', 'delete')),
    actor_user_id uuid,
    db_role common.code NOT NULL,
    request_id uuid,
    changed_columns common.code[] NOT NULL DEFAULT '{}',
    old_values jsonb,
    new_values jsonb,
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE audit.change_log IS 'Who changed what and when on sensitive tables; password/token hashes redacted (SEC-4.7)';
