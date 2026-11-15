-- Indexes for auth.login_attempt. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_login_attempt__email_time ON auth.login_attempt (email, attempted_at DESC);
COMMENT ON INDEX auth.ix_login_attempt__email_time IS 'serves: lockout window per account';

CREATE INDEX brin_login_attempt__attempted_at ON auth.login_attempt USING brin (attempted_at);
COMMENT ON INDEX auth.brin_login_attempt__attempted_at IS 'serves: append-only retention purge (90 days)';
