CREATE TABLE hydration.daily_summary (
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    volume_ml integer NOT NULL DEFAULT 0 CHECK (volume_ml >= 0),
    effective_intake_ml numeric(8, 1) NOT NULL DEFAULT 0 CHECK (effective_intake_ml >= 0),
    food_water_ml numeric(7, 1) NOT NULL DEFAULT 0 CHECK (food_water_ml >= 0),
    workout_sweat_ml numeric(7, 1) NOT NULL DEFAULT 0 CHECK (workout_sweat_ml >= 0),
    daily_need_ml integer CHECK (daily_need_ml BETWEEN 1500 AND 6000),
    goal_completed_at timestamptz,
    calc_version common.version_label REFERENCES ref.calc_version (code),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
) PARTITION BY RANGE (local_date);
COMMENT ON TABLE hydration.daily_summary IS 'Daily hydration totals for reports, streaks and feed; live level is computed on read';
