CREATE TABLE ref.medical_condition (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80),
    kind common.code NOT NULL CHECK (kind IN ('none', 'condition', 'allergy')),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.medical_condition IS 'Selectable conditions and allergies, never free text (OQ-33, list pending)';
