-- V009__create_billing_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/billing.store_product.sql
CREATE TABLE billing.store_product (
    platform common.code NOT NULL CHECK (platform IN ('google_play', 'app_store')),
    product_id common.opaque_ref NOT NULL,
    tier_code common.code NOT NULL REFERENCES ref.subscription_tier (code),
    period common.code NOT NULL CHECK (period IN ('p1m', 'p1y')),
    display_price_inr numeric(8, 2) NOT NULL CHECK (display_price_inr > 0),
    active boolean NOT NULL DEFAULT TRUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (platform, product_id)
);
COMMENT ON TABLE billing.store_product IS 'Store products; prices shown in-app come from the store SDK (OQ-06)';

-- >>> tables/billing.subscription.sql
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

-- >>> indexes/billing.subscription.sql
-- Indexes for billing.subscription. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_subscription__play_token ON billing.subscription (platform, purchase_token) WHERE purchase_token IS NOT NULL;
COMMENT ON INDEX billing.uq_subscription__play_token IS 'serves: UNIQUE: a Play purchase token maps to one subscription (webhooks, reuse protection)';

CREATE UNIQUE INDEX uq_subscription__app_store_txn ON billing.subscription (platform, original_transaction_id) WHERE original_transaction_id IS NOT NULL;
COMMENT ON INDEX billing.uq_subscription__app_store_txn IS 'serves: UNIQUE: an App Store original transaction maps to one subscription';

CREATE INDEX ix_subscription__user_period ON billing.subscription (user_id, current_period_end DESC);
COMMENT ON INDEX billing.ix_subscription__user_period IS 'serves: current entitlement for a user';

CREATE INDEX ix_subscription__renewal_due ON billing.subscription (current_period_end) WHERE status IN ('active', 'in_grace');
COMMENT ON INDEX billing.ix_subscription__renewal_due IS 'serves: reconcile job: subscriptions near expiry';

-- >>> tables/billing.store_transaction.sql
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

-- >>> indexes/billing.store_transaction.sql
-- Indexes for billing.store_transaction. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_store_transaction__subscription_time ON billing.store_transaction (subscription_id, occurred_at DESC);
COMMENT ON INDEX billing.ix_store_transaction__subscription_time IS 'serves: billing history';

-- >>> tables/billing.store_notification.sql
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

-- >>> tables/billing.entitlement_grant.sql
CREATE TABLE billing.entitlement_grant (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    tier_code common.code NOT NULL REFERENCES ref.subscription_tier (code),
    source common.code NOT NULL CHECK (source IN ('referral', 'promo', 'support')),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CHECK (ends_at > starts_at)
);
COMMENT ON TABLE billing.entitlement_grant IS 'Server-side STAR grants (referral rewards, promos, support)';

-- >>> indexes/billing.entitlement_grant.sql
-- Indexes for billing.entitlement_grant. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_entitlement_grant__user_ends ON billing.entitlement_grant (user_id, ends_at DESC);
COMMENT ON INDEX billing.ix_entitlement_grant__user_ends IS 'serves: current entitlement for a user';

-- >>> tables/billing.referral_code.sql
CREATE TABLE billing.referral_code (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    code common.referral_code NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_referral_code__code UNIQUE (code)
);
COMMENT ON TABLE billing.referral_code IS 'One referral code per user';

-- >>> tables/billing.referral.sql
CREATE TABLE billing.referral (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    referrer_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    referred_user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    attributed_at timestamptz NOT NULL DEFAULT now(),
    active_days smallint NOT NULL DEFAULT 0 CHECK (active_days BETWEEN 0 AND 60),
    qualified_at timestamptz,
    status common.code NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'qualified', 'disqualified')),
    disqualify_reason common.code,
    CONSTRAINT uq_referral__referred_user UNIQUE (referred_user_id),
    CHECK (referrer_id <> referred_user_id)
);
COMMENT ON TABLE billing.referral IS 'Referral attribution and progress (doc 06 section 6, OQ-39)';

-- >>> indexes/billing.referral.sql
-- Indexes for billing.referral. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_referral__referrer_status ON billing.referral (referrer_id, status);
COMMENT ON INDEX billing.ix_referral__referrer_status IS 'serves: Refer 5 Friends progress';

-- >>> tables/billing.referral_reward.sql
CREATE TABLE billing.referral_reward (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    referrer_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    reward_days smallint NOT NULL CHECK (reward_days IN (30, 50)),
    grant_id uuid NOT NULL REFERENCES billing.entitlement_grant (id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_referral_reward__referrer UNIQUE (referrer_id)
);
COMMENT ON TABLE billing.referral_reward IS 'One-time referral reward per referrer (OQ-39)';

-- >>> indexes/billing.referral_reward.sql
-- Indexes for billing.referral_reward. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_referral_reward__grant_id ON billing.referral_reward (grant_id);
COMMENT ON INDEX billing.ix_referral_reward__grant_id IS 'serves: FK';
