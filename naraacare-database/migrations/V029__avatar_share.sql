-- V029 (hand-written, 2026-11-08): share an avatar inside NaraaCare only (owner): to Care Circles
-- (a 'shared' card in the circle's Recent Updates) or to connections (an in-app notification). The
-- snapshot is today's values from social.fn_avatar_state, worked out by the database, never sent by
-- the app; it holds numbers only. Shared events belong to one circle, like joined/left.
ALTER TABLE social.activity_event DROP CONSTRAINT activity_event_event_type_check;
ALTER TABLE social.activity_event DROP CONSTRAINT activity_event_check;
ALTER TABLE social.activity_event ADD CONSTRAINT activity_event_event_type_check
    CHECK (event_type IN ('logged', 'goal_completed', 'joined', 'left', 'shared'));
ALTER TABLE social.activity_event ADD CONSTRAINT activity_event_check CHECK (
    (event_type IN ('logged', 'goal_completed') AND avatar_type IS NOT NULL AND circle_id IS NULL)
    OR (event_type IN ('joined', 'left') AND avatar_type IS NULL AND circle_id IS NOT NULL)
    OR (event_type = 'shared' AND avatar_type IS NOT NULL AND circle_id IS NOT NULL)
);
