CREATE TABLE privacy.consent_record (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    purpose common.code NOT NULL CHECK (purpose IN (
        'terms', 'privacy', 'health_data', 'ai_processing', 'circle_sharing', 'marketing'
    )),
    policy_document_id bigint REFERENCES ref.policy_document (id),
    policy_version common.version_label NOT NULL,
    granted boolean NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    app_version common.app_version,
    ip inet
);
COMMENT ON TABLE privacy.consent_record IS 'Append-only consent history with policy version (doc 07 SEC-7.1)';
