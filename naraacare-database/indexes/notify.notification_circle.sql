-- Session 12: circle filter for the in-app notification list (GET /notifications?circle_id=).
CREATE INDEX ix_notification__user_circle_time ON notify.notification (user_id, circle_id, created_at DESC) WHERE circle_id IS NOT NULL;
COMMENT ON INDEX notify.ix_notification__user_circle_time IS 'serves: circle notifications list';
