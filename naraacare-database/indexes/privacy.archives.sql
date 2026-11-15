-- Indexes for the erasure archives (Session 15). Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_consent_archive__archived ON privacy.consent_archive (archived_at);
COMMENT ON INDEX privacy.ix_consent_archive__archived IS 'serves: ops.fn_apply_row_retention (8-year purge)';
CREATE INDEX ix_consent_archive__user_hash ON privacy.consent_archive (user_hash);
COMMENT ON INDEX privacy.ix_consent_archive__user_hash IS 'serves: proof-of-consent lookups by support/legal';
CREATE INDEX ix_transaction_archive__archived ON billing.transaction_archive (archived_at);
COMMENT ON INDEX billing.ix_transaction_archive__archived IS 'serves: ops.fn_apply_row_retention (8-year purge)';
CREATE INDEX ix_deletion_log__completed ON privacy.deletion_log (completed_at);
COMMENT ON INDEX privacy.ix_deletion_log__completed IS 'serves: ops.fn_apply_row_retention (8-year purge)';
