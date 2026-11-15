-- Indexes for billing.referral_reward. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_referral_reward__grant_id ON billing.referral_reward (grant_id);
COMMENT ON INDEX billing.ix_referral_reward__grant_id IS 'serves: FK';
