CREATE TABLE support.feature_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    title common.safe_text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 120),
    benefit common.safe_text NOT NULL CHECK (char_length(benefit) BETWEEN 1 AND 1000),
    forwarded_at timestamptz,
    forward_attempts smallint NOT NULL DEFAULT 0 CHECK (forward_attempts BETWEEN 0 AND 20),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE support.feature_request IS
'Request a feature (doc 04 section 2.13): stored, then forwarded to the support inbox by the worker';
