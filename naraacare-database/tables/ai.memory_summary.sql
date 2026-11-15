CREATE TABLE ai.memory_summary (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    summary common.safe_text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 2000),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ai.memory_summary IS 'Rin AI rolling memory of one user (OQ-37); the user can clear it';
