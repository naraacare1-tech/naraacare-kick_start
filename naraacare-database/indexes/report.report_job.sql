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
