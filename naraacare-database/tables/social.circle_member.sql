CREATE TABLE social.circle_member (
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    role common.code NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    status common.code NOT NULL CHECK (
        status IN ('invited', 'active', 'declined', 'maybe_later', 'left', 'removed')
    ),
    invited_by uuid REFERENCES auth.user_account (id) ON DELETE SET NULL,
    invited_at timestamptz,
    joined_at timestamptz,
    left_at timestamptz,
    last_read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id),
    CHECK (status <> 'active' OR joined_at IS NOT NULL)
);
COMMENT ON TABLE social.circle_member IS
'Membership and invites; seats = active + invited + maybe_later (max 50, doc 06 section 7)';
