-- Indexes for activity.workout. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_workout__user_day ON activity.workout (user_id, local_date) WHERE deleted_at IS NULL;
COMMENT ON INDEX activity.ix_workout__user_day IS 'serves: hydration status + nutrition allowance for a day';

CREATE INDEX ix_workout__user_updated ON activity.workout (user_id, updated_at);
COMMENT ON INDEX activity.ix_workout__user_updated IS 'serves: GET /sync/changes since cursor';
