-- V008__create_activity_hydration_sleep_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/activity.workout.sql
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

-- >>> indexes/activity.workout.sql
-- Indexes for activity.workout. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_workout__user_day ON activity.workout (user_id, local_date) WHERE deleted_at IS NULL;
COMMENT ON INDEX activity.ix_workout__user_day IS 'serves: hydration status + nutrition allowance for a day';

CREATE INDEX ix_workout__user_updated ON activity.workout (user_id, updated_at);
COMMENT ON INDEX activity.ix_workout__user_updated IS 'serves: GET /sync/changes since cursor';

-- >>> tables/hydration.custom_drink.sql
CREATE TABLE hydration.custom_drink (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
    hydration_factor numeric(4, 3) NOT NULL CHECK (hydration_factor BETWEEN 0 AND 1),
    estimated_by common.code NOT NULL CHECK (estimated_by IN ('ai', 'default', 'user')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE hydration.custom_drink IS 'STAR custom drinks; name saved for next use (DOC section 4a)';

-- >>> indexes/hydration.custom_drink.sql
-- Indexes for hydration.custom_drink. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_custom_drink__user_name ON hydration.custom_drink (user_id, lower(name::text)) WHERE deleted_at IS NULL;
COMMENT ON INDEX hydration.uq_custom_drink__user_name IS 'serves: UNIQUE: a custom drink name is saved once per user';

-- >>> tables/hydration.intake.sql
CREATE TABLE hydration.intake (
    id uuid NOT NULL,
    logged_at timestamptz NOT NULL CHECK (logged_at >= '2026-01-01 00:00:00+00'),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    drink_code common.code REFERENCES ref.drink_type (code),
    custom_drink_id uuid REFERENCES hydration.custom_drink (id),
    volume_ml integer NOT NULL,
    hydration_factor numeric(4, 3) NOT NULL CHECK (hydration_factor BETWEEN 0 AND 1),
    effective_ml numeric(7, 1) NOT NULL,
    source common.code NOT NULL CHECK (source IN ('swipe', 'manual', 'preset', 'rin')),
    version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    PRIMARY KEY (id, logged_at),
    CHECK (num_nonnulls(drink_code, custom_drink_id) = 1),
    CHECK (
        volume_ml BETWEEN 1 AND 3000
        OR (volume_ml = -100 AND source = 'swipe' AND drink_code = 'water')
    ),
    CHECK (effective_ml = round(volume_ml * hydration_factor, 1))
) PARTITION BY RANGE (logged_at);
COMMENT ON TABLE hydration.intake IS
'Drinks with factor snapshot; swipe-down is a -100 mL water adjustment (DOC section 4a). Monthly partitions';

-- >>> indexes/hydration.intake.sql
-- Indexes for hydration.intake. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_intake__user_day ON hydration.intake (user_id, local_date, logged_at) INCLUDE (effective_ml, volume_ml) WHERE deleted_at IS NULL;
COMMENT ON INDEX hydration.ix_intake__user_day IS 'serves: GET /hydration/status reads one day in time order (index-only)';

CREATE INDEX ix_intake__user_updated ON hydration.intake (user_id, updated_at);
COMMENT ON INDEX hydration.ix_intake__user_updated IS 'serves: GET /sync/changes since cursor';

CREATE INDEX ix_intake__custom_drink_id ON hydration.intake (custom_drink_id) WHERE custom_drink_id IS NOT NULL;
COMMENT ON INDEX hydration.ix_intake__custom_drink_id IS 'serves: FK';

-- >>> tables/hydration.temperature_log.sql
CREATE TABLE hydration.temperature_log (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    temperature_c numeric(3, 1) NOT NULL CHECK (temperature_c BETWEEN 15 AND 40),
    effective_from timestamptz NOT NULL,
    local_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE hydration.temperature_log IS 'Temperature changes (STAR); each applies from effective_from onward';

-- >>> indexes/hydration.temperature_log.sql
-- Indexes for hydration.temperature_log. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_temperature_log__user_effective ON hydration.temperature_log (user_id, effective_from DESC);
COMMENT ON INDEX hydration.ix_temperature_log__user_effective IS 'serves: latest temperature at or before a time (piecewise drain)';

-- >>> tables/hydration.daily_summary.sql
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

-- >>> tables/sleep.entry.sql
CREATE TABLE sleep.entry (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    sleep_start timestamptz NOT NULL,
    wake_time timestamptz NOT NULL,
    wake_local_date date NOT NULL,
    onset_buffer_min smallint NOT NULL DEFAULT 15 CHECK (onset_buffer_min BETWEEN 0 AND 60),
    wake_buffer_min smallint NOT NULL DEFAULT 15 CHECK (wake_buffer_min BETWEEN 0 AND 60),
    counted_min smallint NOT NULL CHECK (counted_min BETWEEN 0 AND 960),
    version integer NOT NULL DEFAULT 1 CHECK (version >= 1),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CHECK (wake_time > sleep_start AND wake_time - sleep_start <= interval '16 hours'),
    CONSTRAINT ex_sleep_entry__no_overlap EXCLUDE USING gist (
        user_id WITH =,
        tstzrange(sleep_start, wake_time) WITH &&
    ) WHERE (deleted_at IS NULL)
);
COMMENT ON TABLE sleep.entry IS 'Sleep entries (STAR); id = client_entry_id; overlapping entries are impossible';

-- >>> indexes/sleep.entry.sql
-- Indexes for sleep.entry. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_sleep_entry__user_day ON sleep.entry (user_id, wake_local_date DESC) WHERE deleted_at IS NULL;
COMMENT ON INDEX sleep.ix_sleep_entry__user_day IS 'serves: sleep summary for a day, last-2 edit check';

CREATE INDEX ix_sleep_entry__user_updated ON sleep.entry (user_id, updated_at);
COMMENT ON INDEX sleep.ix_sleep_entry__user_updated IS 'serves: GET /sync/changes since cursor';

-- >>> tables/sleep.night_waking.sql
CREATE TABLE sleep.night_waking (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    entry_id uuid NOT NULL REFERENCES sleep.entry (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    woke_at timestamptz NOT NULL,
    back_asleep_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (back_asleep_at > woke_at)
);
COMMENT ON TABLE sleep.night_waking IS 'Night wakings within an entry; user_id duplicated so RLS needs no join';

-- >>> indexes/sleep.night_waking.sql
-- Indexes for sleep.night_waking. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_night_waking__entry_id ON sleep.night_waking (entry_id);
COMMENT ON INDEX sleep.ix_night_waking__entry_id IS 'serves: FK; wakings of an entry';

CREATE INDEX ix_night_waking__user_id ON sleep.night_waking (user_id);
COMMENT ON INDEX sleep.ix_night_waking__user_id IS 'serves: FK; account deletion';

-- >>> tables/sleep.daily_summary.sql
CREATE TABLE sleep.daily_summary (
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    counted_min smallint NOT NULL DEFAULT 0 CHECK (counted_min BETWEEN 0 AND 1440),
    goal_min smallint NOT NULL CHECK (goal_min BETWEEN 240 AND 720),
    score_pct smallint NOT NULL CHECK (score_pct BETWEEN 0 AND 100),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, local_date)
);
COMMENT ON TABLE sleep.daily_summary IS 'Daily sleep total and score (doc 06 section 4)';
