-- Indexes for auth.identity_link. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_identity_link__user_id ON auth.identity_link (user_id);
COMMENT ON INDEX auth.ix_identity_link__user_id IS 'serves: FK; list a user''s linked providers';
