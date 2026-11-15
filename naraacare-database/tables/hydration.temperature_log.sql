CREATE TABLE hydration.temperature_log (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    temperature_c numeric(3, 1) NOT NULL CHECK (temperature_c BETWEEN 15 AND 40),
    effective_from timestamptz NOT NULL,
    local_date date NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE hydration.temperature_log IS 'Temperature changes (STAR); each applies from effective_from onward';
