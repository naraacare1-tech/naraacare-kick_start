-- Indexes for nutrition.meal. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_meal__user_day ON nutrition.meal (user_id, local_date DESC) INCLUDE (meal_type, version) WHERE deleted_at IS NULL;
COMMENT ON INDEX nutrition.ix_meal__user_day IS 'serves: daily meal list, per-day limit count, last-2 edit check (index-only)';

CREATE INDEX ix_meal__user_updated ON nutrition.meal (user_id, updated_at);
COMMENT ON INDEX nutrition.ix_meal__user_updated IS 'serves: GET /sync/changes since cursor';
