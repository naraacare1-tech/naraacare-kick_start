CREATE TABLE activity.workout (
    id uuid NOT NULL,
    performed_at timestamptz NOT NULL CHECK (performed_at >= '2026-01-01 00:00:00+00'),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    workout_type common.code NOT NULL REFERENCES ref.workout_type (code),
    duration_min smallint NOT NULL CHECK (duration_min BETWEEN 1 AND 600),
    sweat_ml numeric(7, 1) NOT NULL CHECK (sweat_ml >= 0),
    kcal integer NOT NULL CHECK (kcal >= 0),
    calc_version common.version_label NOT NULL REFERENCES ref.calc_version (code),
    version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    PRIMARY KEY (id, performed_at)
) PARTITION BY RANGE (performed_at);
COMMENT ON TABLE activity.workout IS 'Workouts (STAR): sweat for hydration, kcal for nutrition allowance';
