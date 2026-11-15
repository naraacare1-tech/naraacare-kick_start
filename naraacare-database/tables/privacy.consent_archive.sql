CREATE TABLE privacy.consent_archive (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_hash common.sha256_hex NOT NULL,
    purpose common.code NOT NULL,
    policy_version common.version_label NOT NULL,
    granted boolean NOT NULL,
    recorded_at timestamptz NOT NULL,
    archived_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privacy.consent_archive IS
'Consent proof kept 8 years after account deletion with the user id hashed (doc 05 section 9, OQ-48)';
