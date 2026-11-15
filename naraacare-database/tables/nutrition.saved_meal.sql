CREATE TABLE nutrition.saved_meal (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE nutrition.saved_meal IS 'User meal templates (max 50 per user, enforced in procedure)';
