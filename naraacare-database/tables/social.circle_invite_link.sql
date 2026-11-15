CREATE TABLE social.circle_invite_link (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    token_hash common.blind_index NOT NULL,
    created_by uuid REFERENCES auth.user_account (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    max_uses smallint NOT NULL DEFAULT 49 CHECK (max_uses BETWEEN 1 AND 49),
    use_count smallint NOT NULL DEFAULT 0 CHECK (use_count >= 0),
    revoked_at timestamptz,
    CONSTRAINT uq_circle_invite_link__token_hash UNIQUE (token_hash),
    CHECK (use_count <= max_uses),
    CHECK (expires_at > created_at)
);
COMMENT ON TABLE social.circle_invite_link IS
'Circle invite links: SHA-256 of a 256-bit token (bearer secret), 7 days, max uses, revocable';
