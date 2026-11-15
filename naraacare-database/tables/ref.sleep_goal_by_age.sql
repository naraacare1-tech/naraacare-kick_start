CREATE TABLE ref.sleep_goal_by_age (
    min_age smallint PRIMARY KEY CHECK (min_age BETWEEN 18 AND 100),
    max_age smallint NOT NULL CHECK (max_age BETWEEN 18 AND 100),
    goal_min smallint NOT NULL CHECK (goal_min BETWEEN 240 AND 720),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CHECK (max_age >= min_age)
);
COMMENT ON TABLE ref.sleep_goal_by_age IS 'Default sleep goal by age (OQ-23, product choice)';
