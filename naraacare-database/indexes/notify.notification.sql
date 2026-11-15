-- Indexes for notify.notification. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_notification__user_created ON notify.notification (user_id, created_at DESC);
COMMENT ON INDEX notify.ix_notification__user_created IS 'serves: notification list paging';

CREATE INDEX ix_notification__user_unread ON notify.notification (user_id) WHERE read_at IS NULL;
COMMENT ON INDEX notify.ix_notification__user_unread IS 'serves: unread badge count';
