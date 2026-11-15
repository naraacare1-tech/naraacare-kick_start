-- V023__create_report_support_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> schemas/060_report_support.sql
-- Report and support schemas (Session 14, doc 05 section 5.8). Same privilege model as the other
-- schemas (roles/010_roles.sql): app roles may resolve names only; api_definer owns the API routines;
-- worker routines are owned by migration_owner and granted to app_worker (doc 05 section 7).
--   * report: PDF report jobs (the file lives in object storage for 7 days) and the aggregated
--     report.v_* views, the only objects the BI login `reporting` may read.
--   * support: Help & Support tickets and feature requests (plain text, common.safe_text).
CREATE SCHEMA IF NOT EXISTS report;
COMMENT ON SCHEMA report IS 'PDF report jobs and aggregated reporting views';
CREATE SCHEMA IF NOT EXISTS support;
COMMENT ON SCHEMA support IS 'Help & Support tickets and feature requests';

GRANT USAGE ON SCHEMA report TO api_definer, app_rw, app_worker, app_readonly, reporting;
GRANT USAGE ON SCHEMA support TO api_definer, app_rw, app_worker, app_readonly;
GRANT CREATE ON SCHEMA report, support TO api_definer;

ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA report
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA support
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;

-- >>> tables/report.report_job.sql
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

-- >>> indexes/report.report_job.sql
-- Indexes for report.report_job. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_report_job__user_recent ON report.report_job (user_id, created_at DESC);
COMMENT ON INDEX report.ix_report_job__user_recent IS
'serves: fn_report_jobs (newest first), daily limit in pr_create_report_job; FK cascade';
CREATE INDEX ix_report_job__queue ON report.report_job (created_at)
WHERE status IN ('queued', 'running');
COMMENT ON INDEX report.ix_report_job__queue IS 'serves: fn_claim_report_jobs (worker queue)';
CREATE INDEX ix_report_job__expiry ON report.report_job (expires_at)
WHERE status = 'ready';
COMMENT ON INDEX report.ix_report_job__expiry IS 'serves: fn_expire_reports (7-day file lifecycle)';

-- >>> tables/support.ticket.sql
CREATE TABLE support.ticket (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    ticket_ref common.opaque_ref NOT NULL UNIQUE CHECK (ticket_ref ~ '^NC-[0-9A-F]{8}$'),
    category common.code NOT NULL CHECK (
        category IN ('app_crash', 'data_sync', 'billing', 'device_link', 'account', 'other')
    ),
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 2000),
    screenshot_key common.object_key CHECK (screenshot_key ~ '^support/'),
    status common.code NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    forwarded_at timestamptz,
    forward_attempts smallint NOT NULL DEFAULT 0 CHECK (forward_attempts BETWEEN 0 AND 20),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE support.ticket IS
'Report a problem (doc 04 section 2.13, OQ-51): stored, then forwarded to the support inbox by the worker';

-- >>> indexes/support.ticket.sql
-- Indexes for support.ticket. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_ticket__user_recent ON support.ticket (user_id, created_at DESC);
COMMENT ON INDEX support.ix_ticket__user_recent IS 'serves: daily limit in pr_create_ticket; FK cascade';
CREATE INDEX ix_ticket__unforwarded ON support.ticket (created_at) WHERE forwarded_at IS NULL;
COMMENT ON INDEX support.ix_ticket__unforwarded IS 'serves: fn_unforwarded (worker email forwarding)';

-- >>> tables/support.feature_request.sql
CREATE TABLE support.feature_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    title common.safe_text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
    benefit common.safe_text NOT NULL CHECK (char_length(benefit) BETWEEN 1 AND 1000),
    forwarded_at timestamptz,
    forward_attempts smallint NOT NULL DEFAULT 0 CHECK (forward_attempts BETWEEN 0 AND 20),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE support.feature_request IS
'Request a feature (doc 04 section 2.13): stored, then forwarded to the support inbox by the worker';

-- >>> indexes/support.feature_request.sql
-- Indexes for support.feature_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_feature_request__user_recent ON support.feature_request (user_id, created_at DESC);
COMMENT ON INDEX support.ix_feature_request__user_recent IS
'serves: daily limit in pr_create_feature_request; FK cascade';
CREATE INDEX ix_feature_request__unforwarded ON support.feature_request (created_at)
WHERE forwarded_at IS NULL;
COMMENT ON INDEX support.ix_feature_request__unforwarded IS 'serves: fn_unforwarded (worker email forwarding)';

-- >>> roles/023_rls_report_support.sql
-- Row-level security for the report and support schemas (Session 14): every row belongs to one user
-- and only that user (app.user_id of the transaction) can see or change it through the API routines,
-- as for the other personal tables (roles/020_rls.sql). Worker routines are owned by migration_owner
-- (the table owner, so RLS does not apply to them) and take no user input.
ALTER TABLE report.report_job ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON report.report_job TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE support.ticket ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON support.ticket TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE support.feature_request ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON support.feature_request TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());
