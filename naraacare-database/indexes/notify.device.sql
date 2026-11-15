-- Indexes for notify.device. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_device__user_active ON notify.device (user_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX notify.ix_device__user_active IS 'serves: push fan-out to a user''s devices';
