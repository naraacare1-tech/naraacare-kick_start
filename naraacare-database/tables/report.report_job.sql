CREATE TABLE report.report_job (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    idempotency_key uuid NOT NULL,
    kind common.code NOT NULL CHECK (kind IN ('monthly', 'custom')),
    period_from date NOT NULL,
    period_to date NOT NULL,
    sections common.code [] NOT NULL CHECK (
        cardinality(sections) BETWEEN 1 AND 4
        AND sections <@ ARRAY['hydration', 'nutrition', 'sleep', 'insights']::common.code []
    ),
    status common.code NOT NULL DEFAULT 'queued' CHECK (
        status IN ('queued', 'running', 'ready', 'failed', 'expired')
    ),
    storage_key common.object_key CHECK (storage_key ~ '^reports/'),
    size_bytes integer CHECK (size_bytes BETWEEN 1 AND 20000000),
    error_code common.code,
    attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 10),
    created_at timestamptz NOT NULL DEFAULT now(),
    started_at timestamptz,
    finished_at timestamptz,
    expires_at timestamptz,
    UNIQUE (user_id, idempotency_key),
    CHECK (period_to >= period_from AND period_to - period_from <= 365),
    CHECK (status <> 'ready' OR (storage_key IS NOT NULL AND size_bytes IS NOT NULL AND expires_at IS NOT NULL))
);
COMMENT ON TABLE report.report_job IS
'PDF report requests (doc 04 section 2.11): queued -> running -> ready (file kept 7 days) or failed';
