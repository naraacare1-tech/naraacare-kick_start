-- Indexes for billing.store_transaction. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_store_transaction__subscription_time ON billing.store_transaction (subscription_id, occurred_at DESC);
COMMENT ON INDEX billing.ix_store_transaction__subscription_time IS 'serves: billing history';
