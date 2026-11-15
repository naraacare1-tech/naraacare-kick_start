CREATE TABLE notify.circle_notification_preference (
    circle_id uuid NOT NULL,
    user_id uuid NOT NULL,
    member_join_leave boolean NOT NULL DEFAULT TRUE,
    circle_updates boolean NOT NULL DEFAULT TRUE,
    goal_completions boolean NOT NULL DEFAULT TRUE,
    avatar_updates boolean NOT NULL DEFAULT FALSE,
    mentions boolean NOT NULL DEFAULT TRUE,
    new_messages boolean NOT NULL DEFAULT FALSE,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id),
    FOREIGN KEY (circle_id, user_id) REFERENCES social.circle_member (circle_id, user_id) ON DELETE CASCADE
);
COMMENT ON TABLE notify.circle_notification_preference IS
'Per-circle notification switches (Figma circle Notification Settings); no row = defaults';
