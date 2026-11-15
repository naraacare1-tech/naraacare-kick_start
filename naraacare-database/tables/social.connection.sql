CREATE TABLE social.connection (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    requester_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    addressee_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    user_low uuid GENERATED ALWAYS AS (least(requester_id, addressee_id)) STORED,
    user_high uuid GENERATED ALWAYS AS (greatest(requester_id, addressee_id)) STORED,
    status common.code NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    responded_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz,
    CHECK (requester_id <> addressee_id)
);
COMMENT ON TABLE social.connection IS 'Connection requests and accepted connections; one live row per pair';
