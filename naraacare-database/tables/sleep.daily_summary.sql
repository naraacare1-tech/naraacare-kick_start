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
