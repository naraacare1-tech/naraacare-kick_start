-- Indexes for ai.pending_action. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_pending_action__user ON ai.pending_action (user_id, created_at DESC);
COMMENT ON INDEX ai.ix_pending_action__user IS 'serves: FK cascade; recent actions of a user';

CREATE INDEX ix_pending_action__conversation ON ai.pending_action (conversation_id);
COMMENT ON INDEX ai.ix_pending_action__conversation IS 'serves: FK cascade on conversation delete';
