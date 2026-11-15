CREATE TABLE audit.security_event (
    id bigint GENERATED ALWAYS AS IDENTITY,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    event_type common.code NOT NULL CHECK (event_type IN (
        'login_failed', 'lockout', 'refresh_reuse', 'validation_rejected', 'authz_denied',
        'rate_limited', 'webhook_rejected', 'admin_access', 'ops_alert', 'purchase_token_reuse'
    )),
    user_id uuid,
    ip inet,
    request_id uuid,
    field_name common.code,
    details jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object' AND pg_column_size(details) < 4096),
    PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE audit.security_event IS 'Security events; never contains rejected payloads (doc 07 section 4.4)';
