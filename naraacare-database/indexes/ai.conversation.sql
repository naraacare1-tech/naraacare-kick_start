-- Indexes for ai.conversation. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_conversation__user_recent ON ai.conversation (user_id, last_message_at DESC)
WHERE deleted_at IS NULL;
COMMENT ON INDEX ai.ix_conversation__user_recent IS 'serves: fn_conversations (newest first); FK cascade';
