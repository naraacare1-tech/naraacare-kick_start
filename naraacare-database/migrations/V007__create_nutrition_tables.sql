-- V007__create_nutrition_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/nutrition.food_item.sql
CREATE TABLE nutrition.food_item (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
    name_normalized text GENERATED ALWAYS AS (lower(name::text)) STORED,
    category_code common.code NOT NULL REFERENCES ref.food_category (code),
    basis common.code NOT NULL CHECK (basis IN ('g', 'ml')),
    density_g_per_ml numeric(4, 3) NOT NULL DEFAULT 1.000 CHECK (density_g_per_ml > 0 AND density_g_per_ml <= 3),
    is_cooked boolean NOT NULL,
    source_ref common.safe_text NOT NULL CHECK (char_length(source_ref) BETWEEN 1 AND 120),
    status common.code NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'pending', 'retired')),
    calories_kcal numeric(9, 3) NOT NULL DEFAULT 0 CHECK (calories_kcal BETWEEN 0 AND 900),
    protein_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (protein_g BETWEEN 0 AND 100),
    carbohydrates_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (carbohydrates_g BETWEEN 0 AND 100),
    fat_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (fat_g BETWEEN 0 AND 100),
    dietary_fiber_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (dietary_fiber_g BETWEEN 0 AND 100),
    total_sugar_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (total_sugar_g BETWEEN 0 AND 100),
    saturated_fat_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (saturated_fat_g BETWEEN 0 AND 100),
    polyunsaturated_fat_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (polyunsaturated_fat_g BETWEEN 0 AND 100),
    monounsaturated_fat_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (monounsaturated_fat_g BETWEEN 0 AND 100),
    trans_fat_g numeric(9, 3) NOT NULL DEFAULT 0 CHECK (trans_fat_g BETWEEN 0 AND 100),
    cholesterol_mg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (cholesterol_mg BETWEEN 0 AND 100000),
    sodium_mg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (sodium_mg BETWEEN 0 AND 100000),
    potassium_mg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (potassium_mg BETWEEN 0 AND 100000),
    calcium_mg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (calcium_mg BETWEEN 0 AND 100000),
    iron_mg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (iron_mg BETWEEN 0 AND 100000),
    vitamin_a_mcg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (vitamin_a_mcg BETWEEN 0 AND 100000),
    vitamin_c_mg numeric(9, 3) NOT NULL DEFAULT 0 CHECK (vitamin_c_mg BETWEEN 0 AND 100000),
    search_vector tsvector GENERATED ALWAYS AS (to_tsvector('simple'::regconfig, name::text)) STORED,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CHECK (protein_g + carbohydrates_g + fat_g <= 100)
);
COMMENT ON TABLE nutrition.food_item IS
'Food DB: 17 nutrients per 100 g (or 100 ml when basis=ml). source_ref is mandatory (OQ-42)';

-- >>> indexes/nutrition.food_item.sql
-- Indexes for nutrition.food_item. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_food_item__name_trgm ON nutrition.food_item USING gin (name_normalized gin_trgm_ops) WHERE status = 'active';
COMMENT ON INDEX nutrition.ix_food_item__name_trgm IS 'serves: nutrition.fn_search_foods typo-tolerant search (moong / mung)';

CREATE INDEX ix_food_item__search_vector ON nutrition.food_item USING gin (search_vector);
COMMENT ON INDEX nutrition.ix_food_item__search_vector IS 'serves: word search on food names';

CREATE INDEX ix_food_item__category_code ON nutrition.food_item (category_code);
COMMENT ON INDEX nutrition.ix_food_item__category_code IS 'serves: admin filter by category';

-- >>> tables/nutrition.food_alias.sql
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

-- >>> indexes/nutrition.food_alias.sql
-- Indexes for nutrition.food_alias. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_food_alias__alias_trgm ON nutrition.food_alias USING gin (alias_normalized gin_trgm_ops);
COMMENT ON INDEX nutrition.ix_food_alias__alias_trgm IS 'serves: search + voice parsing on Hindi/Hinglish aliases (chapati -> roti)';

CREATE INDEX ix_food_alias__food_id ON nutrition.food_alias (food_id);
COMMENT ON INDEX nutrition.ix_food_alias__food_id IS 'serves: FK; aliases of a food';

CREATE UNIQUE INDEX uq_food_alias__food_alias ON nutrition.food_alias (food_id, alias_normalized) WHERE deleted_at IS NULL;
COMMENT ON INDEX nutrition.uq_food_alias__food_alias IS 'serves: UNIQUE: one alias spelling per food; idempotent alias imports';

-- >>> tables/nutrition.food_unit_override.sql
CREATE TABLE nutrition.food_unit_override (
    food_id uuid NOT NULL REFERENCES nutrition.food_item (id) ON DELETE CASCADE,
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    size common.code NOT NULL CHECK (size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    quantity numeric(6, 1) NOT NULL CHECK (quantity > 0 AND quantity <= 2000),
    basis common.code NOT NULL CHECK (basis IN ('g', 'ml')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (food_id, unit_code, size)
);
COMMENT ON TABLE nutrition.food_unit_override IS 'Food-specific portion overriding the category default';

-- >>> tables/nutrition.barcode_product.sql
CREATE TABLE nutrition.barcode_product (
    barcode common.barcode PRIMARY KEY,
    food_id uuid REFERENCES nutrition.food_item (id) ON DELETE SET NULL,
    product_name common.safe_text NOT NULL CHECK (char_length(product_name) BETWEEN 1 AND 160),
    brand common.safe_text CHECK (char_length(brand) BETWEEN 1 AND 80),
    serving_g numeric(6, 1) CHECK (serving_g > 0),
    calories_kcal numeric(9, 3) CHECK (calories_kcal BETWEEN 0 AND 900),
    protein_g numeric(9, 3) CHECK (protein_g BETWEEN 0 AND 100),
    carbohydrates_g numeric(9, 3) CHECK (carbohydrates_g BETWEEN 0 AND 100),
    fat_g numeric(9, 3) CHECK (fat_g BETWEEN 0 AND 100),
    dietary_fiber_g numeric(9, 3) CHECK (dietary_fiber_g BETWEEN 0 AND 100),
    total_sugar_g numeric(9, 3) CHECK (total_sugar_g BETWEEN 0 AND 100),
    saturated_fat_g numeric(9, 3) CHECK (saturated_fat_g BETWEEN 0 AND 100),
    polyunsaturated_fat_g numeric(9, 3) CHECK (polyunsaturated_fat_g BETWEEN 0 AND 100),
    monounsaturated_fat_g numeric(9, 3) CHECK (monounsaturated_fat_g BETWEEN 0 AND 100),
    trans_fat_g numeric(9, 3) CHECK (trans_fat_g BETWEEN 0 AND 100),
    cholesterol_mg numeric(9, 3) CHECK (cholesterol_mg BETWEEN 0 AND 100000),
    sodium_mg numeric(9, 3) CHECK (sodium_mg BETWEEN 0 AND 100000),
    potassium_mg numeric(9, 3) CHECK (potassium_mg BETWEEN 0 AND 100000),
    calcium_mg numeric(9, 3) CHECK (calcium_mg BETWEEN 0 AND 100000),
    iron_mg numeric(9, 3) CHECK (iron_mg BETWEEN 0 AND 100000),
    vitamin_a_mcg numeric(9, 3) CHECK (vitamin_a_mcg BETWEEN 0 AND 100000),
    vitamin_c_mg numeric(9, 3) CHECK (vitamin_c_mg BETWEEN 0 AND 100000),
    source common.code NOT NULL CHECK (source IN ('internal', 'open_food_facts')),
    fetched_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE nutrition.barcode_product IS 'Packaged products by barcode; nutrients per 100 g, NULL when unknown (OQ-44)';

-- >>> indexes/nutrition.barcode_product.sql
-- Indexes for nutrition.barcode_product. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_barcode_product__food_id ON nutrition.barcode_product (food_id) WHERE food_id IS NOT NULL;
COMMENT ON INDEX nutrition.ix_barcode_product__food_id IS 'serves: FK';

-- >>> tables/nutrition.meal.sql
CREATE TABLE nutrition.meal (
    id uuid NOT NULL,
    logged_at timestamptz NOT NULL CHECK (logged_at >= '2026-01-01 00:00:00+00'),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    meal_type common.code NOT NULL CHECK (meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')),
    source common.code NOT NULL CHECK (source IN ('search', 'voice', 'barcode', 'saved', 'rin')),
    hydration_credit boolean NOT NULL DEFAULT FALSE,
    version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    PRIMARY KEY (id, logged_at)
) PARTITION BY RANGE (logged_at);
COMMENT ON TABLE nutrition.meal IS 'Saved meals; id = client_entry_id for idempotent offline sync. Monthly partitions';

-- >>> indexes/nutrition.meal.sql
-- Indexes for nutrition.meal. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_meal__user_day ON nutrition.meal (user_id, local_date DESC) INCLUDE (meal_type, version) WHERE deleted_at IS NULL;
COMMENT ON INDEX nutrition.ix_meal__user_day IS 'serves: daily meal list, per-day limit count, last-2 edit check (index-only)';

CREATE INDEX ix_meal__user_updated ON nutrition.meal (user_id, updated_at);
COMMENT ON INDEX nutrition.ix_meal__user_updated IS 'serves: GET /sync/changes since cursor';

-- >>> tables/nutrition.meal_item.sql
CREATE TABLE nutrition.meal_item (
    id uuid NOT NULL DEFAULT uuidv7(),
    meal_id uuid NOT NULL,
    meal_logged_at timestamptz NOT NULL,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    food_id uuid NOT NULL REFERENCES nutrition.food_item (id),
    quantity numeric(5, 2) NOT NULL CHECK (quantity BETWEEN 0.25 AND 20),
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    unit_size common.code NOT NULL CHECK (unit_size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    consumed_amount numeric(7, 1) NOT NULL CHECK (consumed_amount > 0),
    consumed_basis common.code NOT NULL CHECK (consumed_basis IN ('g', 'ml')),
    calories_kcal numeric(11, 3) NOT NULL DEFAULT 0 CHECK (calories_kcal >= 0),
    protein_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
    carbohydrates_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (carbohydrates_g >= 0),
    fat_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
    dietary_fiber_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (dietary_fiber_g >= 0),
    total_sugar_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (total_sugar_g >= 0),
    saturated_fat_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (saturated_fat_g >= 0),
    polyunsaturated_fat_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (polyunsaturated_fat_g >= 0),
    monounsaturated_fat_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (monounsaturated_fat_g >= 0),
    trans_fat_g numeric(11, 3) NOT NULL DEFAULT 0 CHECK (trans_fat_g >= 0),
    cholesterol_mg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (cholesterol_mg >= 0),
    sodium_mg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (sodium_mg >= 0),
    potassium_mg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (potassium_mg >= 0),
    calcium_mg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (calcium_mg >= 0),
    iron_mg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (iron_mg >= 0),
    vitamin_a_mcg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (vitamin_a_mcg >= 0),
    vitamin_c_mg numeric(11, 3) NOT NULL DEFAULT 0 CHECK (vitamin_c_mg >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    PRIMARY KEY (id, meal_logged_at),
    FOREIGN KEY (meal_id, meal_logged_at) REFERENCES nutrition.meal (id, logged_at) ON DELETE CASCADE
) PARTITION BY RANGE (meal_logged_at);
COMMENT ON TABLE nutrition.meal_item IS
'Meal items with a nutrient SNAPSHOT at log time, so food DB corrections never rewrite history';

-- >>> indexes/nutrition.meal_item.sql
-- Indexes for nutrition.meal_item. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_meal_item__meal ON nutrition.meal_item (meal_id, meal_logged_at);
COMMENT ON INDEX nutrition.ix_meal_item__meal IS 'serves: FK; items of a meal';

CREATE INDEX ix_meal_item__user_food_recent ON nutrition.meal_item (user_id, food_id, meal_logged_at DESC);
COMMENT ON INDEX nutrition.ix_meal_item__user_food_recent IS 'serves: recent foods chips on Add Meal';

CREATE INDEX ix_meal_item__food_id ON nutrition.meal_item (food_id);
COMMENT ON INDEX nutrition.ix_meal_item__food_id IS 'serves: FK; food retirement checks';

-- >>> tables/nutrition.daily_summary.sql
CREATE TABLE nutrition.daily_summary (
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    calories_kcal_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (calories_kcal_total >= 0),
    protein_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (protein_g_total >= 0),
    carbohydrates_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (carbohydrates_g_total >= 0),
    fat_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (fat_g_total >= 0),
    dietary_fiber_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (dietary_fiber_g_total >= 0),
    total_sugar_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (total_sugar_g_total >= 0),
    saturated_fat_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (saturated_fat_g_total >= 0),
    polyunsaturated_fat_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (polyunsaturated_fat_g_total >= 0),
    monounsaturated_fat_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (monounsaturated_fat_g_total >= 0),
    trans_fat_g_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (trans_fat_g_total >= 0),
    cholesterol_mg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (cholesterol_mg_total >= 0),
    sodium_mg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (sodium_mg_total >= 0),
    potassium_mg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (potassium_mg_total >= 0),
    calcium_mg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (calcium_mg_total >= 0),
    iron_mg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (iron_mg_total >= 0),
    vitamin_a_mcg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (vitamin_a_mcg_total >= 0),
    vitamin_c_mg_total numeric(11, 3) NOT NULL DEFAULT 0 CHECK (vitamin_c_mg_total >= 0),
    meal_count smallint NOT NULL DEFAULT 0 CHECK (meal_count BETWEEN 0 AND 8),
    exercise_kcal integer NOT NULL DEFAULT 0 CHECK (exercise_kcal >= 0),
    base_target_kcal integer CHECK (base_target_kcal BETWEEN 1200 AND 10000),
    effective_allowance_kcal integer CHECK (effective_allowance_kcal >= 0),
    calc_version common.version_label REFERENCES ref.calc_version (code),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
) PARTITION BY RANGE (local_date);
COMMENT ON TABLE nutrition.daily_summary IS
'DOC "Table B": running daily totals, updated in the same transaction as meal writes (doc 05 section 8)';

-- >>> tables/nutrition.saved_meal.sql
CREATE TABLE nutrition.saved_meal (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE nutrition.saved_meal IS 'User meal templates (max 50 per user, enforced in procedure)';

-- >>> indexes/nutrition.saved_meal.sql
-- Indexes for nutrition.saved_meal. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_saved_meal__user ON nutrition.saved_meal (user_id) WHERE deleted_at IS NULL;
COMMENT ON INDEX nutrition.ix_saved_meal__user IS 'serves: list saved meals, cap 50 per user';

-- >>> tables/nutrition.saved_meal_item.sql
CREATE TABLE nutrition.saved_meal_item (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    saved_meal_id uuid NOT NULL REFERENCES nutrition.saved_meal (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    food_id uuid NOT NULL REFERENCES nutrition.food_item (id),
    quantity numeric(5, 2) NOT NULL CHECK (quantity BETWEEN 0.25 AND 20),
    unit_code common.code NOT NULL REFERENCES ref.unit (code),
    unit_size common.code NOT NULL CHECK (unit_size IN ('standard', 'small', 'medium', 'large', 'half', 'full')),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE nutrition.saved_meal_item IS 'Items of a saved meal; user_id duplicated so RLS needs no join';

-- >>> indexes/nutrition.saved_meal_item.sql
-- Indexes for nutrition.saved_meal_item. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_saved_meal_item__saved_meal_id ON nutrition.saved_meal_item (saved_meal_id);
COMMENT ON INDEX nutrition.ix_saved_meal_item__saved_meal_id IS 'serves: FK; items of a saved meal';

CREATE INDEX ix_saved_meal_item__user_id ON nutrition.saved_meal_item (user_id);
COMMENT ON INDEX nutrition.ix_saved_meal_item__user_id IS 'serves: FK; account deletion';

CREATE INDEX ix_saved_meal_item__food_id ON nutrition.saved_meal_item (food_id);
COMMENT ON INDEX nutrition.ix_saved_meal_item__food_id IS 'serves: FK';

-- >>> tables/nutrition.food_request.sql
CREATE TABLE nutrition.food_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    food_name common.safe_text NOT NULL CHECK (char_length(food_name) BETWEEN 1 AND 80),
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 500),
    brand common.safe_text CHECK (char_length(brand) BETWEEN 1 AND 80),
    status common.code NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'added', 'rejected')),
    resolved_food_id uuid REFERENCES nutrition.food_item (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE nutrition.food_request IS 'Request New Food (Figma); nutritionists resolve within 24 h';

-- >>> indexes/nutrition.food_request.sql
-- Indexes for nutrition.food_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_food_request__queue ON nutrition.food_request (status, created_at) WHERE status IN ('open', 'in_review');
COMMENT ON INDEX nutrition.ix_food_request__queue IS 'serves: nutritionist work queue';

CREATE INDEX ix_food_request__user_created ON nutrition.food_request (user_id, created_at DESC);
COMMENT ON INDEX nutrition.ix_food_request__user_created IS 'serves: 10 requests per day limit';

CREATE INDEX ix_food_request__resolved_food_id ON nutrition.food_request (resolved_food_id) WHERE resolved_food_id IS NOT NULL;
COMMENT ON INDEX nutrition.ix_food_request__resolved_food_id IS 'serves: FK';
