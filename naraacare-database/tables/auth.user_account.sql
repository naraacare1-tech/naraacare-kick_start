CREATE TABLE auth.user_account (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    email common.email NOT NULL,
    email_verified_at timestamptz,
    password_hash common.argon2_hash,
    status common.code NOT NULL DEFAULT 'pending_verification'
    CHECK (status IN ('pending_verification', 'active', 'locked', 'pending_deletion', 'deleted')),
    role common.code NOT NULL DEFAULT 'user'
    CHECK (role IN ('user', 'nutritionist', 'support', 'admin')),
    failed_login_count smallint NOT NULL DEFAULT 0 CHECK (failed_login_count BETWEEN 0 AND 10000),
    locked_until timestamptz,
    last_login_at timestamptz,
    installation_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CONSTRAINT uq_user_account__email UNIQUE (email)
);
COMMENT ON TABLE auth.user_account IS 'Accounts (email in plain text; password as an Argon2id hash)';
