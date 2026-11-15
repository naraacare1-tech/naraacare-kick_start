-- Indexes for billing.subscription. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_subscription__play_token ON billing.subscription (platform, purchase_token) WHERE purchase_token IS NOT NULL;
COMMENT ON INDEX billing.uq_subscription__play_token IS 'serves: UNIQUE: a Play purchase token maps to one subscription (webhooks, reuse protection)';

CREATE UNIQUE INDEX uq_subscription__app_store_txn ON billing.subscription (platform, original_transaction_id) WHERE original_transaction_id IS NOT NULL;
COMMENT ON INDEX billing.uq_subscription__app_store_txn IS 'serves: UNIQUE: an App Store original transaction maps to one subscription';

CREATE INDEX ix_subscription__user_period ON billing.subscription (user_id, current_period_end DESC);
COMMENT ON INDEX billing.ix_subscription__user_period IS 'serves: current entitlement for a user';

CREATE INDEX ix_subscription__renewal_due ON billing.subscription (current_period_end) WHERE status IN ('active', 'in_grace');
COMMENT ON INDEX billing.ix_subscription__renewal_due IS 'serves: reconcile job: subscriptions near expiry';
