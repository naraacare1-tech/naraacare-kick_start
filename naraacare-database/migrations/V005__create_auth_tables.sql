-- V005__create_auth_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/auth.user_account.sql
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

-- >>> indexes/auth.user_account.sql
-- Indexes for auth.user_account. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_user_account__status_pending ON auth.user_account (status) WHERE status IN ('pending_deletion', 'locked');
COMMENT ON INDEX auth.ix_user_account__status_pending IS 'serves: deletion and unlock jobs scan only accounts in these states';

-- >>> tables/auth.identity_link.sql
CREATE TABLE auth.identity_link (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    provider common.code NOT NULL CHECK (provider IN ('google', 'apple')),
    subject common.opaque_ref NOT NULL,
    email common.email,
    provider_refresh_token common.opaque_token,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CONSTRAINT uq_identity_link__provider_subject UNIQUE (provider, subject)
);
COMMENT ON TABLE auth.identity_link IS 'Google/Apple sign-in links; provider subject and email in plain text';
COMMENT ON COLUMN auth.identity_link.provider_refresh_token IS
'Provider refresh token (Apple), used to revoke access on account deletion';

-- >>> indexes/auth.identity_link.sql
-- Indexes for auth.identity_link. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_identity_link__user_id ON auth.identity_link (user_id);
COMMENT ON INDEX auth.ix_identity_link__user_id IS 'serves: FK; list a user''s linked providers';

-- >>> tables/auth.otp_challenge.sql
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

-- >>> indexes/auth.otp_challenge.sql
-- Indexes for auth.otp_challenge. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_otp_challenge__active ON auth.otp_challenge (email, purpose, created_at DESC) WHERE consumed_at IS NULL;
COMMENT ON INDEX auth.ix_otp_challenge__active IS 'serves: find the active challenge for an email + resend throttling';

CREATE INDEX ix_otp_challenge__user_id ON auth.otp_challenge (user_id);
COMMENT ON INDEX auth.ix_otp_challenge__user_id IS 'serves: FK; cascade on account deletion';

CREATE INDEX ix_otp_challenge__created_at ON auth.otp_challenge (created_at);
COMMENT ON INDEX auth.ix_otp_challenge__created_at IS 'serves: retention purge (7 days)';

-- >>> tables/auth.refresh_token.sql
CREATE TABLE auth.refresh_token (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    family_id uuid NOT NULL,
    parent_id uuid REFERENCES auth.refresh_token (id) ON DELETE SET NULL,
    token_hash common.blind_index NOT NULL,
    installation_id uuid,
    issued_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    revoked_at timestamptz,
    revoked_reason common.code CHECK (revoked_reason IN (
        'rotated', 'logout', 'logout_all', 'reuse_detected', 'password_change', 'deletion', 'admin'
    )),
    CONSTRAINT uq_refresh_token__token_hash UNIQUE (token_hash),
    CHECK (expires_at > issued_at),
    CHECK ((revoked_at IS NULL) = (revoked_reason IS NULL))
);
COMMENT ON TABLE auth.refresh_token IS 'Rotating refresh tokens (SHA-256 only); reuse revokes the family (SEC-1.2)';

-- >>> indexes/auth.refresh_token.sql
-- Indexes for auth.refresh_token. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_refresh_token__family_active ON auth.refresh_token (family_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX auth.ix_refresh_token__family_active IS 'serves: revoke a whole token family on reuse detection';

CREATE INDEX ix_refresh_token__user_active ON auth.refresh_token (user_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX auth.ix_refresh_token__user_active IS 'serves: logout from all devices';

CREATE INDEX ix_refresh_token__parent_id ON auth.refresh_token (parent_id);
COMMENT ON INDEX auth.ix_refresh_token__parent_id IS 'serves: FK (self reference)';

CREATE INDEX ix_refresh_token__expires_at ON auth.refresh_token (expires_at);
COMMENT ON INDEX auth.ix_refresh_token__expires_at IS 'serves: retention purge of expired tokens';

-- >>> tables/auth.password_history.sql
CREATE TABLE auth.password_history (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    password_hash common.argon2_hash NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE auth.password_history IS 'Last 5 password hashes per user (new password must differ, OQ-29)';

-- >>> indexes/auth.password_history.sql
-- Indexes for auth.password_history. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_password_history__user_created ON auth.password_history (user_id, created_at DESC);
COMMENT ON INDEX auth.ix_password_history__user_created IS 'serves: last-5 password reuse check';

-- >>> tables/auth.login_attempt.sql
CREATE TABLE auth.login_attempt (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email common.email NOT NULL,
    ip inet,
    success boolean NOT NULL,
    attempted_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE auth.login_attempt IS 'Login attempts for lockout/backoff; retained 90 days';

-- >>> indexes/auth.login_attempt.sql
-- Indexes for auth.login_attempt. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_login_attempt__email_time ON auth.login_attempt (email, attempted_at DESC);
COMMENT ON INDEX auth.ix_login_attempt__email_time IS 'serves: lockout window per account';

CREATE INDEX brin_login_attempt__attempted_at ON auth.login_attempt USING brin (attempted_at);
COMMENT ON INDEX auth.brin_login_attempt__attempted_at IS 'serves: append-only retention purge (90 days)';
