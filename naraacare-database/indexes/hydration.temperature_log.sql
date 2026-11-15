-- Indexes for hydration.temperature_log. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_temperature_log__user_effective ON hydration.temperature_log (user_id, effective_from DESC);
COMMENT ON INDEX hydration.ix_temperature_log__user_effective IS 'serves: latest temperature at or before a time (piecewise drain)';
