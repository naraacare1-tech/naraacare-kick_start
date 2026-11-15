CREATE TABLE social.chat_mention (
    message_id uuid NOT NULL,
    mentioned_user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    message_created_at timestamptz NOT NULL,
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    PRIMARY KEY (message_id, mentioned_user_id),
    FOREIGN KEY (message_id, message_created_at) REFERENCES social.chat_message (id, created_at) ON DELETE CASCADE
);
COMMENT ON TABLE social.chat_mention IS '@mentions resolved to member user ids (never parsed from text)';
