CREATE TABLE social.user_block (
    blocker_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
COMMENT ON TABLE social.user_block IS 'Blocks: the pair cannot find, connect, invite or mention each other';
