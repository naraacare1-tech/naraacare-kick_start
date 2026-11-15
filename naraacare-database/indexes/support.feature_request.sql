-- Indexes for support.feature_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_feature_request__user_recent ON support.feature_request (user_id, created_at DESC);
COMMENT ON INDEX support.ix_feature_request__user_recent IS
'serves: daily limit in pr_create_feature_request; FK cascade';
CREATE INDEX ix_feature_request__unforwarded ON support.feature_request (created_at)
WHERE forwarded_at IS NULL;
COMMENT ON INDEX support.ix_feature_request__unforwarded IS 'serves: fn_unforwarded (worker email forwarding)';
