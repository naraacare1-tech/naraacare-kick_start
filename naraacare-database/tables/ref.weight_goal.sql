CREATE TABLE ref.weight_goal (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    kcal_delta integer NOT NULL CHECK (kcal_delta BETWEEN -1500 AND 1500),
    kg_per_week numeric(3, 2) NOT NULL CHECK (kg_per_week BETWEEN 0 AND 1.5),
    direction common.code NOT NULL CHECK (direction IN ('loss', 'maintain', 'gain')),
    display_order smallint NOT NULL DEFAULT 0,
    offered boolean NOT NULL DEFAULT TRUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.weight_goal IS 'Goal adjustment matrix (doc 06 section 2.4)';
COMMENT ON COLUMN ref.weight_goal.offered IS 'Shown in the goal picker and accepted as a new choice (V027)';
