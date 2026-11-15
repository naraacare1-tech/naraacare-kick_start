CREATE TABLE ref.workout_type (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    sweat_ml_per_kg_h numeric(4, 1) NOT NULL CHECK (sweat_ml_per_kg_h BETWEEN 0 AND 50),
    met numeric(4, 1) NOT NULL CHECK (met BETWEEN 1 AND 25),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.workout_type IS 'Sweat rates (DOC) and MET values (OQ-16 proposal)';
