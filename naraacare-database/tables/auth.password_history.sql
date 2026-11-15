CREATE TABLE auth.password_history (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    password_hash common.argon2_hash NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE auth.password_history IS 'Last 5 password hashes per user (new password must differ, OQ-29)';
