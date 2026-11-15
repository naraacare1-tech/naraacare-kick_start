CREATE TABLE notify.reminder (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    type common.code NOT NULL CHECK (type IN ('hydration', 'nutrition', 'sleep', 'daily_checkin', 'health_profile')),
    enabled boolean NOT NULL DEFAULT TRUE,
    times time[] NOT NULL DEFAULT '{}' CHECK (cardinality(times) <= 12),
    interval_min smallint CHECK (interval_min BETWEEN 60 AND 240),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_reminder__user_type UNIQUE (user_id, type),
    CHECK (cardinality(times) > 0 OR interval_min IS NOT NULL OR NOT enabled)
);
COMMENT ON TABLE notify.reminder IS 'Reminder schedules in the user''s local time';
