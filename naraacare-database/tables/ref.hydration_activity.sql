CREATE TABLE ref.hydration_activity (
    code common.code PRIMARY KEY CHECK (code IN ('sedentary', 'light', 'active', 'athlete')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    activity_number numeric(4, 2) NOT NULL CHECK (activity_number BETWEEN 1 AND 3),
    athlete_bonus_ml numeric(6, 1) NOT NULL DEFAULT 0 CHECK (athlete_bonus_ml >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.hydration_activity IS 'Yamada 2022 activity numbers (doc 06 section 3.3)';
