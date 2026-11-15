-- Indexes for ai.usage_event. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_usage_event__user_day ON ai.usage_event (user_id, local_date);
COMMENT ON INDEX ai.ix_usage_event__user_day IS 'serves: fn_usage_month (monthly cap), fn_claim_report_jobs; FK cascade';
