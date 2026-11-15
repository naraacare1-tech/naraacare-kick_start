-- Indexes for auth.user_account. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_user_account__status_pending ON auth.user_account (status) WHERE status IN ('pending_deletion', 'locked');
COMMENT ON INDEX auth.ix_user_account__status_pending IS 'serves: deletion and unlock jobs scan only accounts in these states';
