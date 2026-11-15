CREATE TABLE billing.store_transaction (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    subscription_id uuid NOT NULL REFERENCES billing.subscription (id) ON DELETE CASCADE,
    store_transaction_id common.opaque_ref NOT NULL,
    type common.code NOT NULL CHECK (type IN ('purchase', 'renewal', 'refund', 'revoke')),
    amount_micros bigint NOT NULL CHECK (amount_micros >= 0),
    currency common.currency NOT NULL,
    occurred_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_store_transaction__store_id UNIQUE (store_transaction_id)
);
COMMENT ON TABLE billing.store_transaction IS 'Billing history shown in My Subscriptions';
