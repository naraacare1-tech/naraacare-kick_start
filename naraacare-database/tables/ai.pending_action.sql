CREATE TABLE ai.pending_action (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    conversation_id uuid REFERENCES ai.conversation (id) ON DELETE CASCADE,
    kind common.code NOT NULL CHECK (kind IN ('meal', 'drink')),
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object' AND pg_column_size(payload) < 8192),
    status common.code NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'dismissed')),
    result_id uuid,
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    resolved_at timestamptz,
    CHECK ((status = 'pending') = (resolved_at IS NULL))
);
COMMENT ON TABLE ai.pending_action IS
'A log Rin proposed (validated meal items or a drink); nothing is logged until the user accepts';
