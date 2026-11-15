-- Indexes for auth.otp_challenge. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_otp_challenge__active ON auth.otp_challenge (email, purpose, created_at DESC) WHERE consumed_at IS NULL;
COMMENT ON INDEX auth.ix_otp_challenge__active IS 'serves: find the active challenge for an email + resend throttling';

CREATE INDEX ix_otp_challenge__user_id ON auth.otp_challenge (user_id);
COMMENT ON INDEX auth.ix_otp_challenge__user_id IS 'serves: FK; cascade on account deletion';

CREATE INDEX ix_otp_challenge__created_at ON auth.otp_challenge (created_at);
COMMENT ON INDEX auth.ix_otp_challenge__created_at IS 'serves: retention purge (7 days)';
