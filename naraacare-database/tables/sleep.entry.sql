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
