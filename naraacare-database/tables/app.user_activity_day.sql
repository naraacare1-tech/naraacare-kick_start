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
