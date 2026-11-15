-- Indexes for app.user_profile. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_user_profile__username ON app.user_profile (username) WHERE deleted_at IS NULL;
COMMENT ON INDEX app.uq_user_profile__username IS 'serves: UNIQUE: username availability and @mention lookup';

CREATE INDEX ix_user_profile__username_prefix ON app.user_profile (username text_pattern_ops) WHERE deleted_at IS NULL;
COMMENT ON INDEX app.ix_user_profile__username_prefix IS 'serves: Find People prefix search (username LIKE ''aar%'')';
