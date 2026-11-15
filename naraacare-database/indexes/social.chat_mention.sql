-- Indexes for social.chat_mention. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_chat_mention__user_time ON social.chat_mention (mentioned_user_id, message_created_at DESC);
COMMENT ON INDEX social.ix_chat_mention__user_time IS 'serves: my mentions; FK';

CREATE INDEX ix_chat_mention__message ON social.chat_mention (message_id, message_created_at);
COMMENT ON INDEX social.ix_chat_mention__message IS 'serves: FK to chat_message (cascade)';

CREATE INDEX ix_chat_mention__circle ON social.chat_mention (circle_id);
COMMENT ON INDEX social.ix_chat_mention__circle IS 'serves: FK; cascade on circle deletion';
