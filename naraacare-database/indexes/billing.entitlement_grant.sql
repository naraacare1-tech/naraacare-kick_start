-- Indexes for billing.entitlement_grant. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_entitlement_grant__user_ends ON billing.entitlement_grant (user_id, ends_at DESC);
COMMENT ON INDEX billing.ix_entitlement_grant__user_ends IS 'serves: current entitlement for a user';
