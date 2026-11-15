-- V011__create_audit_ops_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/audit.change_log.sql
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

-- >>> indexes/audit.change_log.sql
-- Indexes for audit.change_log. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX brin_change_log__occurred_at ON audit.change_log USING brin (occurred_at);
COMMENT ON INDEX audit.brin_change_log__occurred_at IS 'serves: append-only time-range scans';

CREATE INDEX ix_change_log__table_row ON audit.change_log (table_name, row_pk);
COMMENT ON INDEX audit.ix_change_log__table_row IS 'serves: history of one row';

-- >>> tables/audit.security_event.sql
CREATE TABLE audit.security_event (
    id bigint GENERATED ALWAYS AS IDENTITY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    event_type common.code NOT NULL CHECK (event_type IN (
        'login_failed', 'lockout', 'refresh_reuse', 'validation_rejected', 'authz_denied',
        'rate_limited', 'webhook_rejected', 'admin_access', 'ops_alert'
    )),
    user_id uuid,
    ip inet,
    request_id uuid,
    field_name common.code,
    details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object' AND pg_column_size(details) < 4096),
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE audit.security_event IS 'Security events; never contains rejected payloads (doc 07 section 4.4)';

-- >>> indexes/audit.security_event.sql
-- Indexes for audit.security_event. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_security_event__type_time ON audit.security_event (event_type, occurred_at DESC);
COMMENT ON INDEX audit.ix_security_event__type_time IS 'serves: alerting on event spikes';

CREATE INDEX ix_security_event__user_time ON audit.security_event (user_id, occurred_at DESC);
COMMENT ON INDEX audit.ix_security_event__user_time IS 'serves: investigate a user';

CREATE INDEX brin_security_event__occurred_at ON audit.security_event USING brin (occurred_at);
COMMENT ON INDEX audit.brin_security_event__occurred_at IS 'serves: append-only time-range scans';

-- >>> tables/ops.partition_config.sql
CREATE TABLE ops.partition_config (
    parent_table common.code PRIMARY KEY,
    bound_type common.code NOT NULL CHECK (bound_type IN ('timestamptz', 'date')),
    premake_months smallint NOT NULL DEFAULT 3 CHECK (premake_months BETWEEN 1 AND 12),
    retention_months smallint CHECK (retention_months > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ops.partition_config IS 'Monthly partitioned tables and how far ahead to create partitions';
