-- V010__create_notify_privacy_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> tables/notify.device.sql
CREATE TABLE notify.device (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    installation_id uuid NOT NULL,
    platform common.code NOT NULL CHECK (platform IN ('android', 'ios')),
    push_token common.opaque_token,
    app_version common.app_version NOT NULL,
    last_seen_at timestamptz NOT NULL DEFAULT now(),
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_device__user_installation UNIQUE (user_id, installation_id)
);
COMMENT ON TABLE notify.device IS 'App installations and FCM push tokens';

-- >>> indexes/notify.device.sql
-- Indexes for notify.device. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_device__user_active ON notify.device (user_id) WHERE revoked_at IS NULL;
COMMENT ON INDEX notify.ix_device__user_active IS 'serves: push fan-out to a user''s devices';

-- >>> tables/notify.notification_preference.sql
CREATE TABLE notify.notification_preference (
    user_id uuid PRIMARY KEY REFERENCES auth.user_account (id) ON DELETE CASCADE,
    goal_completions boolean NOT NULL DEFAULT TRUE,
    streak_milestones boolean NOT NULL DEFAULT TRUE,
    health_insights boolean NOT NULL DEFAULT TRUE,
    hydration_reminders boolean NOT NULL DEFAULT TRUE,
    nutrition_reminders boolean NOT NULL DEFAULT TRUE,
    sleep_reminders boolean NOT NULL DEFAULT TRUE,
    daily_checkin boolean NOT NULL DEFAULT FALSE,
    health_profile_reminders boolean NOT NULL DEFAULT TRUE,
    connection_requests boolean NOT NULL DEFAULT TRUE,
    connection_activity boolean NOT NULL DEFAULT TRUE,
    reports_ready boolean NOT NULL DEFAULT TRUE,
    subscription_payments boolean NOT NULL DEFAULT TRUE,
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE notify.notification_preference IS 'Personal notification toggles (Figma Notification Settings)';

-- >>> tables/notify.reminder.sql
CREATE TABLE notify.reminder (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    type common.code NOT NULL CHECK (type IN ('hydration', 'nutrition', 'sleep', 'daily_checkin', 'health_profile')),
    enabled boolean NOT NULL DEFAULT TRUE,
    times time[] NOT NULL DEFAULT '{}' CHECK (cardinality(times) <= 12),
    interval_min smallint CHECK (interval_min BETWEEN 60 AND 240),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_reminder__user_type UNIQUE (user_id, type),
    CHECK (cardinality(times) > 0 OR interval_min IS NOT NULL OR NOT enabled)
);
COMMENT ON TABLE notify.reminder IS 'Reminder schedules in the user''s local time';

-- >>> tables/notify.notification.sql
CREATE TABLE notify.notification (
    id uuid NOT NULL DEFAULT uuidv7(),
    created_at timestamptz NOT NULL DEFAULT now(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    circle_id uuid,
    category common.code NOT NULL,
    template_code common.code NOT NULL,
    params jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(params) = 'object' AND pg_column_size(params) < 2048),
    deep_link common.deep_link,
    read_at timestamptz,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE notify.notification IS
'In-app notification list; template code + params (codes/numbers only), localised by the app';

-- >>> indexes/notify.notification.sql
-- Indexes for notify.notification. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_notification__user_created ON notify.notification (user_id, created_at DESC);
COMMENT ON INDEX notify.ix_notification__user_created IS 'serves: notification list paging';

CREATE INDEX ix_notification__user_unread ON notify.notification (user_id) WHERE read_at IS NULL;
COMMENT ON INDEX notify.ix_notification__user_unread IS 'serves: unread badge count';

-- >>> tables/privacy.consent_record.sql
CREATE TABLE privacy.consent_record (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    purpose common.code NOT NULL CHECK (purpose IN (
        'terms', 'privacy', 'health_data', 'ai_processing', 'circle_sharing', 'marketing'
    )),
    policy_document_id bigint REFERENCES ref.policy_document (id),
    policy_version common.version_label NOT NULL,
    granted boolean NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT now(),
    app_version common.app_version,
    ip inet
);
COMMENT ON TABLE privacy.consent_record IS 'Append-only consent history with policy version (doc 07 SEC-7.1)';

-- >>> indexes/privacy.consent_record.sql
-- Indexes for privacy.consent_record. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_consent_record__user_purpose_time ON privacy.consent_record (user_id, purpose, recorded_at DESC);
COMMENT ON INDEX privacy.ix_consent_record__user_purpose_time IS 'serves: current consent per purpose';

-- >>> tables/privacy.export_request.sql
CREATE TABLE privacy.export_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    idempotency_key uuid NOT NULL,
    status common.code NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'ready', 'failed', 'expired')),
    requested_at timestamptz NOT NULL DEFAULT now(),
    ready_at timestamptz,
    object_key common.object_key,
    expires_at timestamptz,
    CONSTRAINT uq_export_request__user_key UNIQUE (user_id, idempotency_key)
);
COMMENT ON TABLE privacy.export_request IS 'Data export requests (right to access)';

-- >>> indexes/privacy.export_request.sql
-- Indexes for privacy.export_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_export_request__user_requested ON privacy.export_request (user_id, requested_at DESC);
COMMENT ON INDEX privacy.ix_export_request__user_requested IS 'serves: 1 export per 24 h check';

-- >>> tables/privacy.deletion_request.sql
CREATE TABLE privacy.deletion_request (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    requested_at timestamptz NOT NULL DEFAULT now(),
    scheduled_for timestamptz NOT NULL,
    status common.code NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'cancelled', 'completed')),
    cancelled_at timestamptz,
    completed_at timestamptz,
    CHECK (scheduled_for > requested_at)
);
COMMENT ON TABLE privacy.deletion_request IS 'Account deletion with a 30-day grace period (OQ-47)';

-- >>> indexes/privacy.deletion_request.sql
-- Indexes for privacy.deletion_request. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_deletion_request__due ON privacy.deletion_request (scheduled_for) WHERE status = 'scheduled';
COMMENT ON INDEX privacy.ix_deletion_request__due IS 'serves: deletion worker';

CREATE INDEX ix_deletion_request__user_id ON privacy.deletion_request (user_id);
COMMENT ON INDEX privacy.ix_deletion_request__user_id IS 'serves: FK; cancel on sign-in during grace';

-- >>> tables/privacy.retention_policy.sql
CREATE TABLE privacy.retention_policy (
    table_name common.code PRIMARY KEY,
    retention_days integer NOT NULL CHECK (retention_days > 0),
    action common.code NOT NULL CHECK (action IN ('purge', 'anonymize')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privacy.retention_policy IS 'Per-table retention (doc 05 section 9, pending legal approval OQ-48)';
