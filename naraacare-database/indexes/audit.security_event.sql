-- Indexes for audit.security_event. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_security_event__type_time ON audit.security_event (event_type, occurred_at DESC);
COMMENT ON INDEX audit.ix_security_event__type_time IS 'serves: alerting on event spikes';

CREATE INDEX ix_security_event__user_time ON audit.security_event (user_id, occurred_at DESC);
COMMENT ON INDEX audit.ix_security_event__user_time IS 'serves: investigate a user';

CREATE INDEX brin_security_event__occurred_at ON audit.security_event USING brin (occurred_at);
COMMENT ON INDEX audit.brin_security_event__occurred_at IS 'serves: append-only time-range scans';
