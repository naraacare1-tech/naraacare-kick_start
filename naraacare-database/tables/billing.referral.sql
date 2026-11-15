CREATE TABLE billing.referral (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    referrer_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    referred_user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    attributed_at timestamptz NOT NULL DEFAULT now(),
    active_days smallint NOT NULL DEFAULT 0 CHECK (active_days BETWEEN 0 AND 60),
    qualified_at timestamptz,
    status common.code NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'qualified', 'disqualified')),
    disqualify_reason common.code,
    CONSTRAINT uq_referral__referred_user UNIQUE (referred_user_id),
    CHECK (referrer_id <> referred_user_id)
);
COMMENT ON TABLE billing.referral IS 'Referral attribution and progress (doc 06 section 6, OQ-39)';
