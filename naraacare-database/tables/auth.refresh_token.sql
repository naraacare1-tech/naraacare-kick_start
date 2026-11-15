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
