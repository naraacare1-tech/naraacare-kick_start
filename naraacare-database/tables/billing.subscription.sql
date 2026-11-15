CREATE TABLE billing.subscription (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    platform common.code NOT NULL,
    product_id common.opaque_ref NOT NULL,
    purchase_token common.opaque_token,
    original_transaction_id common.opaque_ref CHECK (original_transaction_id ~ '^[0-9]{1,32}$'),
    status common.code NOT NULL CHECK (status IN (
        'active', 'in_grace', 'on_hold', 'paused', 'canceled', 'expired', 'revoked', 'refunded'
    )),
    auto_renew boolean NOT NULL,
    current_period_start timestamptz NOT NULL,
    current_period_end timestamptz NOT NULL,
    environment common.code NOT NULL CHECK (environment IN ('sandbox', 'production')),
    last_verified_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    FOREIGN KEY (platform, product_id) REFERENCES billing.store_product (platform, product_id),
    CHECK (current_period_end > current_period_start),
    CHECK (
        (platform = 'google_play' AND purchase_token IS NOT NULL AND original_transaction_id IS NULL)
        OR (platform = 'app_store' AND original_transaction_id IS NOT NULL AND purchase_token IS NULL)
    )
);
COMMENT ON TABLE billing.subscription IS
'Server-verified store subscriptions; a purchase token / transaction belongs to exactly one user';
COMMENT ON COLUMN billing.subscription.purchase_token IS
'Google Play purchase token (uniqueness, reconcile, refunds); NULL for App Store';
