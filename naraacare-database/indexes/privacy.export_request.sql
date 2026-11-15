-- Indexes for privacy.export_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_export_request__user_requested ON privacy.export_request (user_id, requested_at DESC);
COMMENT ON INDEX privacy.ix_export_request__user_requested IS 'serves: 1 export per 24 h check';
CREATE INDEX ix_export_request__queue ON privacy.export_request (requested_at)
WHERE status IN ('queued', 'running');
COMMENT ON INDEX privacy.ix_export_request__queue IS 'serves: ops.fn_claim_exports (worker queue, S15)';
CREATE INDEX ix_export_request__expiry ON privacy.export_request (expires_at) WHERE status = 'ready';
COMMENT ON INDEX privacy.ix_export_request__expiry IS 'serves: ops.fn_expire_exports (7-day file lifecycle, S15)';
