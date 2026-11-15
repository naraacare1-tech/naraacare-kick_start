-- Indexes for privacy.deletion_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_deletion_request__due ON privacy.deletion_request (scheduled_for) WHERE status = 'scheduled';
COMMENT ON INDEX privacy.ix_deletion_request__due IS 'serves: deletion worker';

CREATE INDEX ix_deletion_request__user_id ON privacy.deletion_request (user_id);
COMMENT ON INDEX privacy.ix_deletion_request__user_id IS 'serves: FK; cancel on sign-in during grace';
