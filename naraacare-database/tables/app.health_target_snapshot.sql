CREATE TABLE app.health_target_snapshot (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    effective_date date NOT NULL,
    calc_version common.version_label NOT NULL REFERENCES ref.calc_version (code),
    inputs jsonb NOT NULL CHECK (jsonb_typeof(inputs) = 'object' AND pg_column_size(inputs) < 4096),
    bmi numeric(4, 1) NOT NULL CHECK (bmi BETWEEN 5 AND 100),
    bmi_category common.code NOT NULL REFERENCES ref.bmi_category (code),
    bmr_kcal integer NOT NULL CHECK (bmr_kcal BETWEEN 300 AND 6000),
    tdee_kcal integer NOT NULL CHECK (tdee_kcal BETWEEN 200 AND 10000),
    goal_delta_kcal integer NOT NULL CHECK (goal_delta_kcal BETWEEN -1500 AND 1500),
    calculated_target_kcal integer NOT NULL,
    base_target_kcal integer NOT NULL CHECK (base_target_kcal BETWEEN 1200 AND 10000),
    safety_override boolean NOT NULL,
    carbs_g integer NOT NULL CHECK (carbs_g >= 0),
    fat_g integer NOT NULL CHECK (fat_g >= 0),
    protein_g integer NOT NULL CHECK (protein_g >= 0),
    lean_body_weight_kg numeric(5, 2) NOT NULL CHECK (lean_body_weight_kg > 0),
    water_movement_ml numeric(7, 1) NOT NULL CHECK (water_movement_ml > 0),
    base_water_need_ml integer NOT NULL CHECK (base_water_need_ml BETWEEN 1500 AND 6000),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_health_target_snapshot__user_date UNIQUE (user_id, effective_date)
);
COMMENT ON TABLE app.health_target_snapshot IS
'Targets per user per day of change; editing the profile replaces today only, past days are kept';
