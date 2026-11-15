-- V006__create_app_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/app.user_profile.sql
CREATE TABLE app.user_profile (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    full_name common.safe_text CHECK (char_length(full_name) BETWEEN 1 AND 100),
    username common.username,
    username_changed_at timestamptz,
    biological_sex common.code CHECK (biological_sex IN ('female', 'male')),
    avatar_code common.code REFERENCES ref.avatar (code),
    age_years smallint CHECK (age_years BETWEEN 18 AND 100),
    age_recorded_on date,
    height_cm numeric(4, 1) CHECK (height_cm BETWEEN 120 AND 230),
    weight_kg numeric(5, 2) CHECK (weight_kg BETWEEN 30 AND 250),
    target_weight_kg numeric(5, 2) CHECK (target_weight_kg BETWEEN 30 AND 250),
    weight_goal_code common.code REFERENCES ref.weight_goal (code),
    activity_level_code common.code REFERENCES ref.activity_level (code),
    body_type_code common.code REFERENCES ref.body_type (code),
    medical_conditions common.code[] CHECK (cardinality(medical_conditions) <= 20),
    height_unit common.code NOT NULL DEFAULT 'cm' CHECK (height_unit IN ('cm', 'ft_in')),
    weight_unit common.code NOT NULL DEFAULT 'kg' CHECK (weight_unit IN ('kg', 'lb')),
    temperature_unit common.code NOT NULL DEFAULT 'c' CHECK (temperature_unit IN ('c', 'f')),
    timezone common.iana_timezone NOT NULL DEFAULT 'Asia/Kolkata',
    locale common.locale NOT NULL DEFAULT 'en',
    sleep_start_local time NOT NULL DEFAULT '23:00',
    wake_local time NOT NULL DEFAULT '07:00',
    sleep_goal_min smallint CHECK (sleep_goal_min BETWEEN 240 AND 720),
    onboarding_step smallint NOT NULL DEFAULT 0 CHECK (onboarding_step BETWEEN 0 AND 6),
    onboarding_completed_at timestamptz,
    biometric_lock boolean NOT NULL DEFAULT FALSE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CHECK ((age_years IS NULL) = (age_recorded_on IS NULL)),
    CHECK (sleep_start_local <> wake_local)
);
COMMENT ON TABLE app.user_profile IS
'Profile and onboarding answers (metric units). Name and condition codes in plain text';

-- >>> indexes/app.user_profile.sql
-- Indexes for app.user_profile. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_user_profile__username ON app.user_profile (username) WHERE deleted_at IS NULL;
COMMENT ON INDEX app.uq_user_profile__username IS 'serves: UNIQUE: username availability and @mention lookup';

CREATE INDEX ix_user_profile__username_prefix ON app.user_profile (username text_pattern_ops) WHERE deleted_at IS NULL;
COMMENT ON INDEX app.ix_user_profile__username_prefix IS 'serves: Find People prefix search (username LIKE ''aar%'')';

-- >>> tables/app.health_target_snapshot.sql
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

-- >>> tables/app.user_activity_day.sql
CREATE TABLE app.user_activity_day (
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    has_hydration boolean NOT NULL DEFAULT FALSE,
    has_nutrition boolean NOT NULL DEFAULT FALSE,
    has_sleep boolean NOT NULL DEFAULT FALSE,
    first_logged_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);
COMMENT ON TABLE app.user_activity_day IS 'One row per user per active day: streaks and referral activity';

-- >>> tables/app.user_streak.sql
CREATE TABLE app.user_streak (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    current_streak integer NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
    longest_streak integer NOT NULL DEFAULT 0 CHECK (longest_streak >= current_streak),
    last_active_date date,
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE app.user_streak IS 'Denormalised streak cache for the Profile header (doc 05 section 8)';
