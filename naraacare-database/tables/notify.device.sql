CREATE TABLE notify.device (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    installation_id uuid NOT NULL,
    platform common.code NOT NULL CHECK (platform IN ('android', 'ios')),
    push_token common.opaque_token,
    app_version common.app_version NOT NULL,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_device__user_installation UNIQUE (user_id, installation_id)
);
COMMENT ON TABLE notify.device IS 'App installations and FCM push tokens';
