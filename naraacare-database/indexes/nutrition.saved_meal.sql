-- Indexes for nutrition.saved_meal. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_saved_meal__user ON nutrition.saved_meal (user_id) WHERE deleted_at IS NULL;
COMMENT ON INDEX nutrition.ix_saved_meal__user IS 'serves: list saved meals, cap 50 per user';
