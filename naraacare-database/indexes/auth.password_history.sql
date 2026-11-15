-- Indexes for auth.password_history. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_password_history__user_created ON auth.password_history (user_id, created_at DESC);
COMMENT ON INDEX auth.ix_password_history__user_created IS 'serves: last-5 password reuse check';
