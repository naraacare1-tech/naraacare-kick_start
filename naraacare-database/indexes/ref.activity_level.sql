-- Indexes for ref.activity_level. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_activity_level__hydration_activity_code ON ref.activity_level (hydration_activity_code);
COMMENT ON INDEX ref.ix_activity_level__hydration_activity_code IS 'serves: FK within ref';
