CREATE TABLE nutrition.food_alias (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    food_id uuid NOT NULL REFERENCES nutrition.food_item (id) ON DELETE CASCADE,
    alias common.safe_text NOT NULL CHECK (char_length(alias) BETWEEN 1 AND 60),
    alias_normalized text GENERATED ALWAYS AS (lower(alias::text)) STORED,
    language common.code NOT NULL CHECK (language IN ('en', 'hi', 'hinglish')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE nutrition.food_alias IS 'Alternative names incl. Hindi/Hinglish for search and voice parsing';
