CREATE TABLE auth.otp_challenge (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid REFERENCES auth.user_account (id) ON DELETE CASCADE,
    email common.email NOT NULL,
    purpose common.code NOT NULL CHECK (purpose IN ('email_verification', 'password_reset', 'reauth')),
    code common.otp_code NOT NULL,
    expires_at timestamptz NOT NULL,
    attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 3),
    send_count smallint NOT NULL DEFAULT 1 CHECK (send_count BETWEEN 1 AND 5),
    last_sent_at timestamptz NOT NULL DEFAULT now(),
    consumed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at)
);
COMMENT ON TABLE auth.otp_challenge IS '6-digit email OTPs (plain text): 5 min, 3 attempts, single use (DOC section 2.4)';
