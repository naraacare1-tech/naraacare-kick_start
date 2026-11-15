-- Indexes for social.circle_share. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_circle_share__user_avatar ON social.circle_share (user_id, avatar_type);
COMMENT ON INDEX social.ix_circle_share__user_avatar IS 'serves: feed and visibility checks per owner';
