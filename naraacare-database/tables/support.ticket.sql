CREATE TABLE support.ticket (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    ticket_ref common.opaque_ref NOT NULL UNIQUE CHECK (ticket_ref ~ '^NC-[0-9A-F]{8}$'),
    category common.code NOT NULL CHECK (
        category IN ('app_crash', 'data_sync', 'billing', 'device_link', 'account', 'other')
    ),
    description common.safe_text NOT NULL CHECK (char_length(description) BETWEEN 1 AND 2000),
    screenshot_key common.object_key CHECK (screenshot_key ~ '^support/'),
    status common.code NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed')),
    forwarded_at timestamptz,
    forward_attempts smallint NOT NULL DEFAULT 0 CHECK (forward_attempts BETWEEN 0 AND 20),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE support.ticket IS
'Report a problem (doc 04 section 2.13, OQ-51): stored, then forwarded to the support inbox by the worker';
