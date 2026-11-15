-- Indexes for billing.referral. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_referral__referrer_status ON billing.referral (referrer_id, status);
COMMENT ON INDEX billing.ix_referral__referrer_status IS 'serves: Refer 5 Friends progress';
