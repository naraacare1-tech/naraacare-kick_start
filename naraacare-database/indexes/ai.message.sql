-- Indexes for ai.message. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_message__conversation_time ON ai.message (conversation_id, created_at DESC);
COMMENT ON INDEX ai.ix_message__conversation_time IS 'serves: fn_messages (keyset by time); FK cascade';

CREATE UNIQUE INDEX ux_message__client_id ON ai.message (user_id, client_message_id)
WHERE client_message_id IS NOT NULL;
COMMENT ON INDEX ai.ux_message__client_id IS 'serves: idempotent prompt (retry after a lost response); FK';
