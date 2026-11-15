-- Indexes for social.activity_event. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_activity_event__actor_avatar_time ON social.activity_event (actor_id, avatar_type, occurred_at DESC);
COMMENT ON INDEX social.ix_activity_event__actor_avatar_time IS 'serves: circle feed (fan-out-on-read); FK';

CREATE INDEX ix_activity_event__circle_time ON social.activity_event (circle_id, occurred_at DESC) WHERE circle_id IS NOT NULL;
COMMENT ON INDEX social.ix_activity_event__circle_time IS 'serves: join/leave events in the circle feed; FK';
