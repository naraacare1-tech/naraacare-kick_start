CREATE TABLE app.user_streak (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    current_streak integer NOT NULL DEFAULT 0 CHECK (current_streak >= 0),
    longest_streak integer NOT NULL DEFAULT 0 CHECK (longest_streak >= current_streak),
    last_active_date date,
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE app.user_streak IS 'Denormalised streak cache for the Profile header (doc 05 section 8)';
