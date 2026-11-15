-- Indexes for hydration.intake. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_intake__user_day ON hydration.intake (user_id, local_date, logged_at) INCLUDE (effective_ml, volume_ml) WHERE deleted_at IS NULL;
COMMENT ON INDEX hydration.ix_intake__user_day IS 'serves: GET /hydration/status reads one day in time order (index-only)';

CREATE INDEX ix_intake__user_updated ON hydration.intake (user_id, updated_at);
COMMENT ON INDEX hydration.ix_intake__user_updated IS 'serves: GET /sync/changes since cursor';

CREATE INDEX ix_intake__custom_drink_id ON hydration.intake (custom_drink_id) WHERE custom_drink_id IS NOT NULL;
COMMENT ON INDEX hydration.ix_intake__custom_drink_id IS 'serves: FK';
