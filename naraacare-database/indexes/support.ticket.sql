-- Indexes for support.ticket. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_ticket__user_recent ON support.ticket (user_id, created_at DESC);
COMMENT ON INDEX support.ix_ticket__user_recent IS 'serves: daily limit in pr_create_ticket; FK cascade';
CREATE INDEX ix_ticket__unforwarded ON support.ticket (created_at) WHERE forwarded_at IS NULL;
COMMENT ON INDEX support.ix_ticket__unforwarded IS 'serves: fn_unforwarded (worker email forwarding)';
