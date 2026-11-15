-- Indexes for privacy.consent_record. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_consent_record__user_purpose_time ON privacy.consent_record (user_id, purpose, recorded_at DESC);
COMMENT ON INDEX privacy.ix_consent_record__user_purpose_time IS 'serves: current consent per purpose';
