CREATE TABLE billing.referral_code (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    code common.referral_code NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_referral_code__code UNIQUE (code)
);
COMMENT ON TABLE billing.referral_code IS 'One referral code per user';
