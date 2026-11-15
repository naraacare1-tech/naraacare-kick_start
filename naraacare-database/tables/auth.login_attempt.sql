CREATE TABLE auth.login_attempt (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email common.email NOT NULL,
    ip inet,
    success boolean NOT NULL,
    attempted_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE auth.login_attempt IS 'Login attempts for lockout/backoff; retained 90 days';
