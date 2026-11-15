-- V024__privacy_export_erasure: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/privacy.consent_archive.sql
CREATE TABLE privacy.consent_archive (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_hash common.sha256_hex NOT NULL,
    purpose common.code NOT NULL,
    policy_version common.version_label NOT NULL,
    granted boolean NOT NULL,
    recorded_at timestamptz NOT NULL,
    archived_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privacy.consent_archive IS
'Consent proof kept 8 years after account deletion with the user id hashed (doc 05 section 9, OQ-48)';

-- >>> tables/billing.transaction_archive.sql
CREATE TABLE billing.transaction_archive (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_hash common.sha256_hex NOT NULL,
    platform common.code NOT NULL,
    product_id common.opaque_ref NOT NULL,
    store_transaction_id common.opaque_ref NOT NULL,
    type common.code NOT NULL,
    amount_micros bigint NOT NULL CHECK (amount_micros >= 0),
    currency common.currency NOT NULL,
    occurred_at timestamptz NOT NULL,
    archived_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE billing.transaction_archive IS
'Store transactions kept 8 years after account deletion for tax records, user link anonymised (doc 05 s.9)';

-- >>> tables/privacy.deletion_log.sql
CREATE TABLE privacy.deletion_log (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_hash common.sha256_hex NOT NULL,
    requested_at timestamptz NOT NULL,
    completed_at timestamptz NOT NULL DEFAULT now(),
    rows_archived integer NOT NULL DEFAULT 0 CHECK (rows_archived >= 0)
);
COMMENT ON TABLE privacy.deletion_log IS
'Proof that an account was erased (no personal data: hashed user id and times only)';

-- >>> indexes/privacy.archives.sql
-- Indexes for the erasure archives (Session 15). Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_consent_archive__archived ON privacy.consent_archive (archived_at);
COMMENT ON INDEX privacy.ix_consent_archive__archived IS 'serves: ops.fn_apply_row_retention (8-year purge)';
CREATE INDEX ix_consent_archive__user_hash ON privacy.consent_archive (user_hash);
COMMENT ON INDEX privacy.ix_consent_archive__user_hash IS 'serves: proof-of-consent lookups by support/legal';
CREATE INDEX ix_transaction_archive__archived ON billing.transaction_archive (archived_at);
COMMENT ON INDEX billing.ix_transaction_archive__archived IS 'serves: ops.fn_apply_row_retention (8-year purge)';
CREATE INDEX ix_deletion_log__completed ON privacy.deletion_log (completed_at);
COMMENT ON INDEX privacy.ix_deletion_log__completed IS 'serves: ops.fn_apply_row_retention (8-year purge)';

-- >>> roles/024_rls_privacy_archives.sql
-- Erasure archives (Session 15): RLS on with no policy, so no API role can read or write them; only the
-- ops erasure and retention routines (owned by migration_owner, the table owner) touch them.
ALTER TABLE privacy.consent_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE billing.transaction_archive ENABLE ROW LEVEL SECURITY;
ALTER TABLE privacy.deletion_log ENABLE ROW LEVEL SECURITY;

-- Hand-written part (Session 15): columns and indexes added to existing canonical files
-- (tables/privacy.export_request.sql, tables/privacy.deletion_request.sql, indexes/privacy.export_request.sql).
ALTER TABLE privacy.export_request
    ADD COLUMN started_at timestamptz,
    ADD COLUMN attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 10),
    ADD COLUMN size_bytes bigint CHECK (size_bytes BETWEEN 1 AND 2000000000),
    ADD COLUMN error_code common.code,
    ADD CONSTRAINT ck_export_request__key CHECK (object_key IS NULL OR object_key ~ '^exports/');
ALTER TABLE privacy.deletion_request ADD COLUMN receipt_sent_at timestamptz;

CREATE INDEX ix_export_request__queue ON privacy.export_request (requested_at)
WHERE status IN ('queued', 'running');
COMMENT ON INDEX privacy.ix_export_request__queue IS 'serves: ops.fn_claim_exports (worker queue, S15)';
CREATE INDEX ix_export_request__expiry ON privacy.export_request (expires_at) WHERE status = 'ready';
COMMENT ON INDEX privacy.ix_export_request__expiry IS 'serves: ops.fn_expire_exports (7-day file lifecycle, S15)';

