CREATE TABLE social.circle_share (
    circle_id uuid NOT NULL,
    user_id uuid NOT NULL,
    avatar_type common.code NOT NULL CHECK (avatar_type IN ('hydration', 'nutrition', 'sleep')),
    shared_since timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id, avatar_type),
    FOREIGN KEY (circle_id, user_id) REFERENCES social.circle_member (circle_id, user_id) ON DELETE CASCADE
);
COMMENT ON TABLE social.circle_share IS
'Avatars a member shares with a circle; ">= 1 share" is enforced by the procedures';
