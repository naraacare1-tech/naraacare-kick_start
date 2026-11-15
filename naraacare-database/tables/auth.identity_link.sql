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
