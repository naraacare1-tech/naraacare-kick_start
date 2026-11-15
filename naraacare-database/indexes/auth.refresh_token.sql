-- Indexes for auth.refresh_token. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_refresh_token__family_active ON auth.refresh_token (family_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX auth.ix_refresh_token__family_active IS 'serves: revoke a whole token family on reuse detection';

CREATE INDEX ix_refresh_token__user_active ON auth.refresh_token (user_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX auth.ix_refresh_token__user_active IS 'serves: logout from all devices';

CREATE INDEX ix_refresh_token__parent_id ON auth.refresh_token (parent_id);
COMMENT ON INDEX auth.ix_refresh_token__parent_id IS 'serves: FK (self reference)';

CREATE INDEX ix_refresh_token__expires_at ON auth.refresh_token (expires_at);
COMMENT ON INDEX auth.ix_refresh_token__expires_at IS 'serves: retention purge of expired tokens';
