CREATE TABLE hydration.custom_drink (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    hydration_factor numeric(4, 3) NOT NULL CHECK (hydration_factor BETWEEN 0 AND 1),
    estimated_by common.code NOT NULL CHECK (estimated_by IN ('ai', 'default', 'user')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE hydration.custom_drink IS 'STAR custom drinks; name saved for next use (DOC section 4a)';
