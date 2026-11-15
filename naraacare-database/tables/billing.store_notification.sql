CREATE TABLE billing.store_notification (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    platform common.code NOT NULL CHECK (platform IN ('google_play', 'app_store')),
    notification_uid common.opaque_ref NOT NULL,
    type common.code NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    status common.code NOT NULL DEFAULT 'received' CHECK (status IN ('received', 'processed', 'ignored', 'failed')),
    payload_sha256 common.sha256_hex NOT NULL,
    CONSTRAINT uq_store_notification__platform_uid UNIQUE (platform, notification_uid)
);
COMMENT ON TABLE billing.store_notification IS 'RTDN / App Store Server Notifications; unique id makes processing idempotent';
