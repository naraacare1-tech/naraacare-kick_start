CREATE TABLE ai.usage_event (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    feature common.code NOT NULL CHECK (
        feature IN ('chat', 'title', 'memory', 'drink_estimate', 'voice_parse', 'report_insight')
    ),
    model common.opaque_ref NOT NULL CHECK (model ~ '^[a-z0-9][a-z0-9.-]{0,63}$'),
    input_tokens integer NOT NULL CHECK (input_tokens >= 0),
    output_tokens integer NOT NULL CHECK (output_tokens >= 0),
    cache_write_tokens integer NOT NULL DEFAULT 0 CHECK (cache_write_tokens >= 0),
    cache_read_tokens integer NOT NULL DEFAULT 0 CHECK (cache_read_tokens >= 0),
    cost_micro_inr bigint NOT NULL DEFAULT 0 CHECK (cost_micro_inr >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ai.usage_event IS
'Usage per model call: tokens and cost; the monthly Rin cap is the sum of cost_micro_inr (V026)';
COMMENT ON COLUMN ai.usage_event.cost_micro_inr IS
'Cost of the call in micro-rupees, from the API''s configured model prices at call time';
