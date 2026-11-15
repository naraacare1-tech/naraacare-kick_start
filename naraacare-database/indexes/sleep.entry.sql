-- Indexes for sleep.entry. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_sleep_entry__user_day ON sleep.entry (user_id, wake_local_date DESC) WHERE deleted_at IS NULL;
COMMENT ON INDEX sleep.ix_sleep_entry__user_day IS 'serves: sleep summary for a day, last-2 edit check';

CREATE INDEX ix_sleep_entry__user_updated ON sleep.entry (user_id, updated_at);
COMMENT ON INDEX sleep.ix_sleep_entry__user_updated IS 'serves: GET /sync/changes since cursor';
