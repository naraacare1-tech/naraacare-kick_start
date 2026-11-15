CREATE TABLE ai.conversation (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    title common.safe_text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
    last_message_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE ai.conversation IS 'Rin AI chats of one user (title from the first prompt); soft delete';
