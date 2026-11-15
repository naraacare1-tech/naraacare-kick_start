CREATE TABLE privacy.export_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    idempotency_key uuid NOT NULL,
    status common.code NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'ready', 'failed', 'expired')),
    requested_at timestamptz NOT NULL DEFAULT now(),
    ready_at timestamptz,
    object_key common.object_key,
    expires_at timestamptz,
    started_at timestamptz,
    attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 10),
    size_bytes bigint CHECK (size_bytes BETWEEN 1 AND 2000000000),
    error_code common.code,
    CONSTRAINT uq_export_request__user_key UNIQUE (user_id, idempotency_key),
    CONSTRAINT ck_export_request__key CHECK (object_key IS NULL OR object_key ~ '^exports/')
);
COMMENT ON TABLE privacy.export_request IS 'Data export requests (right to access)';
