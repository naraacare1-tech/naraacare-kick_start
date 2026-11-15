-- V022__create_ai_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> schemas/050_ai.sql
-- AI schema (Session 13, doc 05 section 5.7): Rin AI conversations, messages, memory, proposed
-- logs (pending actions) and token usage. Same privilege model as the other schemas
-- (roles/010_roles.sql): app roles may resolve names only; api_definer owns the API routines.
-- Plain text (doc 07 section 6.1); every text column is common.safe_text (no markup). Model output
-- is sanitised to plain text by the API before it is stored.
CREATE SCHEMA IF NOT EXISTS ai;
COMMENT ON SCHEMA ai IS 'Rin AI: conversations, messages, memory, pending actions, token usage';

GRANT USAGE ON SCHEMA ai TO api_definer, app_rw, app_worker, app_readonly;
GRANT CREATE ON SCHEMA ai TO api_definer;

ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA ai
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA ai
GRANT USAGE, SELECT ON SEQUENCES TO api_definer;

-- >>> tables/ai.conversation.sql
CREATE TABLE ai.conversation (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    title common.safe_text NOT NULL CHECK (char_length(title) BETWEEN 1 AND 80),
    last_message_at timestamptz NOT NULL DEFAULT now(),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE ai.conversation IS 'Rin AI chats of one user (title from the first prompt); soft delete';

-- >>> indexes/ai.conversation.sql
-- Indexes for ai.conversation. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_conversation__user_recent ON ai.conversation (user_id, last_message_at DESC)
WHERE deleted_at IS NULL;
COMMENT ON INDEX ai.ix_conversation__user_recent IS 'serves: fn_conversations (newest first); FK cascade';

-- >>> tables/ai.message.sql
CREATE TABLE ai.message (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    conversation_id uuid NOT NULL REFERENCES ai.conversation (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    role common.code NOT NULL CHECK (role IN ('user', 'assistant')),
    content common.safe_text NOT NULL CHECK (char_length(content) BETWEEN 1 AND 8000),
    client_message_id uuid,
    action_id uuid,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (role = 'assistant' OR client_message_id IS NOT NULL)
);
COMMENT ON TABLE ai.message IS
'Rin AI messages: user prompts (idempotent by client id) and plain-text model replies';

-- >>> indexes/ai.message.sql
-- Indexes for ai.message. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_message__conversation_time ON ai.message (conversation_id, created_at DESC);
COMMENT ON INDEX ai.ix_message__conversation_time IS 'serves: fn_messages (keyset by time); FK cascade';

CREATE UNIQUE INDEX ux_message__client_id ON ai.message (user_id, client_message_id)
WHERE client_message_id IS NOT NULL;
COMMENT ON INDEX ai.ux_message__client_id IS 'serves: idempotent prompt (retry after a lost response); FK';

-- >>> tables/ai.memory_summary.sql
CREATE TABLE ai.memory_summary (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    summary common.safe_text NOT NULL CHECK (char_length(summary) BETWEEN 1 AND 2000),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ai.memory_summary IS 'Rin AI rolling memory of one user (OQ-37); the user can clear it';

-- >>> tables/ai.pending_action.sql
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

-- >>> indexes/ai.pending_action.sql
-- Indexes for ai.pending_action. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_pending_action__user ON ai.pending_action (user_id, created_at DESC);
COMMENT ON INDEX ai.ix_pending_action__user IS 'serves: FK cascade; recent actions of a user';

CREATE INDEX ix_pending_action__conversation ON ai.pending_action (conversation_id);
COMMENT ON INDEX ai.ix_pending_action__conversation IS 'serves: FK cascade on conversation delete';

-- >>> tables/ai.usage_event.sql
CREATE TABLE ai.usage_event (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    local_date date NOT NULL,
    feature common.code NOT NULL CHECK (
        feature IN ('chat', 'title', 'memory', 'drink_estimate', 'voice_parse', 'report_insight')
    ),
    model text NOT NULL CHECK (model ~ '^[a-z0-9][a-z0-9.-]{0,63}$'),
    input_tokens integer NOT NULL CHECK (input_tokens >= 0),
    output_tokens integer NOT NULL CHECK (output_tokens >= 0),
    cache_write_tokens integer NOT NULL DEFAULT 0 CHECK (cache_write_tokens >= 0),
    cache_read_tokens integer NOT NULL DEFAULT 0 CHECK (cache_read_tokens >= 0),
    created_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE ai.usage_event IS
'Token usage per model call (doc 06 section 8: the allowance counts input + output + cache-write)';

-- >>> indexes/ai.usage_event.sql
-- Indexes for ai.usage_event. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_usage_event__user_day ON ai.usage_event (user_id, local_date);
COMMENT ON INDEX ai.ix_usage_event__user_day IS 'serves: fn_usage_today (allowance check); FK cascade';

-- >>> roles/022_rls_ai.sql
-- Row-level security for the ai schema (Session 13): every row belongs to one user and only that
-- user (app.user_id of the transaction) can see or change it, as for the other personal tables
-- (roles/020_rls.sql). Rin never reads another user's data (OQ-37).
ALTER TABLE ai.conversation ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.conversation TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.message ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.message TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.memory_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.memory_summary TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.pending_action ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.pending_action TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());

ALTER TABLE ai.usage_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON ai.usage_event TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());
