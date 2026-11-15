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
