-- Indexes for social.user_block. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_user_block__blocked ON social.user_block (blocked_id);
COMMENT ON INDEX social.ix_user_block__blocked IS 'serves: "hidden both ways" checks; FK';
