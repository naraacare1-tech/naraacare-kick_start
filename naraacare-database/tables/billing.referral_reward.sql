CREATE TABLE billing.referral_reward (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    referrer_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    reward_days smallint NOT NULL CHECK (reward_days IN (30, 50)),
    grant_id uuid NOT NULL REFERENCES billing.entitlement_grant (id),
    granted_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_referral_reward__referrer UNIQUE (referrer_id)
);
COMMENT ON TABLE billing.referral_reward IS 'One-time referral reward per referrer (OQ-39)';
