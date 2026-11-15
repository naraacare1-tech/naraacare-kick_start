CREATE TABLE ref.policy_document (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    doc_type common.code NOT NULL CHECK (doc_type IN ('terms', 'privacy', 'licenses')),
    version common.version_label NOT NULL,
    url common.https_url NOT NULL,
    content_sha256 common.sha256_hex,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (doc_type, version)
);
COMMENT ON TABLE ref.policy_document IS 'Versioned legal documents; consent records point here (doc 07 SEC-7.1)';
