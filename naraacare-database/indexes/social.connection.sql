-- Indexes for social.connection. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_connection__pair ON social.connection (user_low, user_high) WHERE deleted_at IS NULL;
COMMENT ON INDEX social.uq_connection__pair IS 'serves: UNIQUE: one relationship per pair; status lookups';

CREATE INDEX ix_connection__addressee_pending ON social.connection (addressee_id) WHERE status = 'pending' AND deleted_at IS NULL;
COMMENT ON INDEX social.ix_connection__addressee_pending IS 'serves: incoming connection requests';

CREATE INDEX ix_connection__requester_status ON social.connection (requester_id, status) WHERE deleted_at IS NULL;
COMMENT ON INDEX social.ix_connection__requester_status IS 'serves: my connections and sent requests';

CREATE INDEX ix_connection__addressee_status ON social.connection (addressee_id, status) WHERE deleted_at IS NULL;
COMMENT ON INDEX social.ix_connection__addressee_status IS 'serves: my connections (as addressee)';
