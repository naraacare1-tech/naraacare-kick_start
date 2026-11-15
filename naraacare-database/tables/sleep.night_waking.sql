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
