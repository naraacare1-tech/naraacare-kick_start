CREATE TABLE billing.transaction_archive (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_hash common.sha256_hex NOT NULL,
    platform common.code NOT NULL,
    product_id common.opaque_ref NOT NULL,
    store_transaction_id common.opaque_ref NOT NULL,
    type common.code NOT NULL,
    amount_micros bigint NOT NULL CHECK (amount_micros >= 0),
    currency common.currency NOT NULL,
    occurred_at timestamptz NOT NULL,
    archived_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE billing.transaction_archive IS
'Store transactions kept 8 years after account deletion for tax records, user link anonymised (doc 05 s.9)';
