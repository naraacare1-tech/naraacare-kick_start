CREATE TABLE social.chat_message (
    id uuid NOT NULL DEFAULT uuidv7(),
    created_at timestamptz NOT NULL DEFAULT now(),
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    sender_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    client_message_id uuid NOT NULL,
    body common.safe_text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    deleted_at timestamptz,
    deleted_by uuid,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE social.chat_message IS
'Circle chat (plain text, no markup: common.safe_text); deleted messages keep the row, body hidden';
