CREATE TABLE ai.message (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    conversation_id uuid NOT NULL REFERENCES ai.conversation (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    role common.code NOT NULL CHECK (role IN ('user', 'assistant')),
    content common.safe_text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 8000),
    client_message_id uuid,
    action_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (role = 'assistant' OR client_message_id IS NOT NULL)
);
COMMENT ON TABLE ai.message IS
'Rin AI messages: user prompts (idempotent by client id) and plain-text model replies';
