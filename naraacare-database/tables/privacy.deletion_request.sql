CREATE TABLE privacy.deletion_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    requested_at timestamptz NOT NULL DEFAULT now(),
    scheduled_for timestamptz NOT NULL,
    status common.code NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'cancelled', 'completed')),
    cancelled_at timestamptz,
    completed_at timestamptz,
    receipt_sent_at timestamptz,
    CHECK (scheduled_for > requested_at)
);
COMMENT ON TABLE privacy.deletion_request IS 'Account deletion with a 30-day grace period (OQ-47)';
