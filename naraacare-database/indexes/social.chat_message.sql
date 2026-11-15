-- Indexes for social.chat_message. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_chat_message__circle_time ON social.chat_message (circle_id, created_at DESC);
COMMENT ON INDEX social.ix_chat_message__circle_time IS 'serves: chat paging; unread counts; FK';

CREATE UNIQUE INDEX uq_chat_message__client_id ON social.chat_message (sender_id, client_message_id, created_at);
COMMENT ON INDEX social.uq_chat_message__client_id IS
'serves: UNIQUE: idempotent send (the procedure also checks the last day under a lock); FK';
