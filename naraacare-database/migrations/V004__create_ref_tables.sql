-- V004__create_ref_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/ref.subscription_tier.sql
CREATE TABLE ref.subscription_tier (
    code common.code PRIMARY KEY CHECK (code IN ('standard', 'star')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.subscription_tier IS 'STANDARD (free) and STAR (paid) tiers';

-- >>> tables/ref.feature_entitlement.sql
CREATE TABLE ref.feature_entitlement (
    tier_code common.code NOT NULL REFERENCES ref.subscription_tier (code),
    feature_code common.code NOT NULL,
    enabled boolean NOT NULL,
    limit_value integer CHECK (limit_value >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tier_code, feature_code)
);
COMMENT ON TABLE ref.feature_entitlement IS 'Server-side tier matrix (doc 04 section 3); limit_value e.g. meal logs per day';

-- >>> tables/ref.calc_version.sql
CREATE TABLE ref.calc_version (
    code common.version_label PRIMARY KEY,
    effective_from date NOT NULL,
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 500),
    approved_by common.safe_text CHECK (char_length(approved_by) BETWEEN 1 AND 100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.calc_version IS 'Version of calculation constants; snapshots record the version they used';

-- >>> tables/ref.calc_constant.sql
CREATE TABLE ref.calc_constant (
    calc_version common.version_label NOT NULL REFERENCES ref.calc_version (code),
    key common.code NOT NULL,
    value numeric NOT NULL,
    unit common.code NOT NULL,
    source common.safe_text NOT NULL CHECK (char_length(source) BETWEEN 1 AND 200),
    is_product_choice boolean NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (calc_version, key)
);
COMMENT ON TABLE ref.calc_constant IS 'Every formula constant from doc 06; is_product_choice = needs expert review';

-- >>> tables/ref.hydration_activity.sql
CREATE TABLE ref.hydration_activity (
    code common.code PRIMARY KEY CHECK (code IN ('sedentary', 'active', 'athlete')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    activity_number numeric(4, 2) NOT NULL CHECK (activity_number BETWEEN 1 AND 3),
    athlete_bonus_ml numeric(6, 1) NOT NULL DEFAULT 0 CHECK (athlete_bonus_ml >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.hydration_activity IS 'Yamada 2022 activity numbers (doc 06 section 3.3)';

-- >>> tables/ref.activity_level.sql
CREATE TABLE ref.activity_level (
    code common.code PRIMARY KEY
    CHECK (code IN ('sedentary', 'lightly_active', 'moderately_active', 'very_active')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    onboarding_label common.safe_text NOT NULL CHECK (char_length(onboarding_label) BETWEEN 1 AND 80),
    tdee_multiplier numeric(4, 3) NOT NULL CHECK (tdee_multiplier > 0 AND tdee_multiplier <= 2.5),
    hydration_activity_code common.code NOT NULL REFERENCES ref.hydration_activity (code),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.activity_level IS 'Onboarding activity answer to TDEE multiplier and hydration activity (OQ-12, OQ-13)';

-- >>> indexes/ref.activity_level.sql
-- Indexes for ref.activity_level. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_activity_level__hydration_activity_code ON ref.activity_level (hydration_activity_code);
COMMENT ON INDEX ref.ix_activity_level__hydration_activity_code IS 'serves: FK within ref';

-- >>> tables/ref.body_type.sql
CREATE TABLE ref.body_type (
    code common.code PRIMARY KEY CHECK (code IN ('ectomorph', 'mesomorph', 'endomorph')),
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    lbw_factor numeric(4, 3) NOT NULL CHECK (lbw_factor BETWEEN 0.8 AND 1.2),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.body_type IS 'Lean-body-weight factor per body type (doc 06 section 3.2, product choice)';

-- >>> tables/ref.weight_goal.sql
CREATE TABLE ref.weight_goal (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    kcal_delta integer NOT NULL CHECK (kcal_delta BETWEEN -1500 AND 1500),
    kg_per_week numeric(3, 2) NOT NULL CHECK (kg_per_week BETWEEN 0 AND 1.5),
    direction common.code NOT NULL CHECK (direction IN ('loss', 'maintain', 'gain')),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.weight_goal IS 'Goal adjustment matrix (doc 06 section 2.4)';

-- >>> tables/ref.bmi_category.sql
CREATE TABLE ref.bmi_category (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 60),
    min_bmi numeric(4, 1) NOT NULL CHECK (min_bmi >= 0),
    max_bmi_exclusive numeric(4, 1) CHECK (max_bmi_exclusive > min_bmi),
    blocked_goal_codes common.code[] NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.bmi_category IS 'BMI guardrails: half-open ranges and blocked goals (doc 06 section 2.3)';

-- >>> tables/ref.sleep_goal_by_age.sql
CREATE TABLE ref.sleep_goal_by_age (
    min_age smallint PRIMARY KEY CHECK (min_age BETWEEN 18 AND 100),
    max_age smallint NOT NULL CHECK (max_age BETWEEN 18 AND 100),
    goal_min smallint NOT NULL CHECK (goal_min BETWEEN 240 AND 720),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (max_age >= min_age)
);
COMMENT ON TABLE ref.sleep_goal_by_age IS 'Default sleep goal by age (OQ-23, product choice)';

-- >>> tables/ref.avatar.sql
CREATE TABLE ref.avatar (
    code common.code PRIMARY KEY,
    sex common.code NOT NULL CHECK (sex IN ('female', 'male')),
    body_type_code common.code NOT NULL REFERENCES ref.body_type (code),
    asset_key common.asset_key NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (sex, body_type_code)
);
COMMENT ON TABLE ref.avatar IS 'Base avatars: 2 sexes x 3 body types (OQ-56)';

-- >>> tables/ref.medical_condition.sql
CREATE TABLE ref.medical_condition (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80),
    kind common.code NOT NULL CHECK (kind IN ('none', 'condition', 'allergy')),
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.medical_condition IS 'Selectable conditions and allergies, never free text (OQ-33, list pending)';

-- >>> tables/ref.drink_type.sql
CREATE TABLE ref.drink_type (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    hydration_factor numeric(4, 3) NOT NULL CHECK (hydration_factor BETWEEN 0 AND 1),
    tier_required common.code NOT NULL REFERENCES ref.subscription_tier (code),
    is_alcohol boolean NOT NULL DEFAULT FALSE,
    display_order smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.drink_type IS 'Drink hydration factors (doc 06 section 3.6) and tier (OQ-05)';

-- >>> tables/ref.workout_type.sql
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

-- >>> tables/ref.nutrient.sql
CREATE TABLE ref.nutrient (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    unit common.code NOT NULL CHECK (unit IN ('kcal', 'g', 'mg', 'mcg')),
    tier_required common.code NOT NULL REFERENCES ref.subscription_tier (code),
    display_order smallint NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.nutrient IS 'The 17 tracked nutrients; STANDARD sees 6 (doc 01 section 4)';

-- >>> tables/ref.food_category.sql
CREATE TABLE ref.food_category (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.food_category IS 'Indian measurement matrix categories (doc 06 section 2.10)';

-- >>> tables/ref.unit.sql
CREATE TABLE ref.unit (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 30),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.unit IS 'Portion units shown in the UI (katori, piece, glass and so on)';

-- >>> tables/ref.food_category_unit.sql
CREATE TABLE ref.food_category_unit (
    category_code common.code NOT NULL REFERENCES ref.food_category (code),
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    size common.code NOT NULL CHECK (size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    quantity numeric(6, 1) NOT NULL CHECK (quantity > 0 AND quantity <= 2000),
    basis common.code NOT NULL CHECK (basis IN ('g', 'ml')),
    is_default boolean NOT NULL DEFAULT FALSE,
    is_confirmed boolean NOT NULL DEFAULT FALSE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (category_code, unit_code, size)
);
COMMENT ON TABLE ref.food_category_unit IS
'Default portion per category, unit and size; is_confirmed=false marks proposals awaiting sign-off (OQ-59)';

-- >>> indexes/ref.food_category_unit.sql
-- Indexes for ref.food_category_unit. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_food_category_unit__default ON ref.food_category_unit (category_code) WHERE is_default;
COMMENT ON INDEX ref.uq_food_category_unit__default IS 'serves: UNIQUE: at most one default portion per food category';

-- >>> tables/ref.policy_document.sql
CREATE TABLE ref.policy_document (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_type common.code NOT NULL CHECK (doc_type IN ('terms', 'privacy', 'licenses')),
    version common.version_label NOT NULL,
    url common.https_url NOT NULL,
    content_sha256 common.sha256_hex,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (doc_type, version)
);
COMMENT ON TABLE ref.policy_document IS 'Versioned legal documents; consent records point here (doc 07 SEC-7.1)';

-- >>> tables/ref.feature_flag.sql
CREATE TABLE ref.feature_flag (
    key common.code PRIMARY KEY,
    enabled boolean NOT NULL,
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 200),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.feature_flag IS 'Server-side feature flags';

-- >>> tables/ref.wallpaper.sql
CREATE TABLE ref.wallpaper (
    code common.code PRIMARY KEY,
    label common.safe_text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 40),
    asset_key common.asset_key NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ref.wallpaper IS 'Care Circle wallpapers (assets pending design)';
