-- V021__create_social_tables: generated from canonical DDL by tools/build_baseline.py.
-- Immutable once merged. Later changes go into new migrations (V014+) plus the canonical files.

-- >>> schemas/040_social.sql
-- Social schema (Session 12, doc 05 section 5.6): connections, blocks, Care Circles, chat, feed.
-- Same privilege model as the other schemas (roles/010_roles.sql): app roles may resolve names but
-- get no table privileges; api_definer owns the API routines and gets DML on new tables.
-- Data is stored in plain text (doc 07 section 6.1); only invite-link tokens are hashed (bearer
-- secrets, like refresh tokens).
CREATE SCHEMA IF NOT EXISTS social;
COMMENT ON SCHEMA social IS 'Connections, blocks, Care Circles, chat and the activity feed';

GRANT USAGE ON SCHEMA social TO api_definer, app_rw, app_worker, app_readonly;
GRANT CREATE ON SCHEMA social TO api_definer;

ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA social
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO api_definer;
ALTER DEFAULT PRIVILEGES FOR ROLE migration_owner IN SCHEMA social
GRANT USAGE, SELECT ON SEQUENCES TO api_definer;

-- >>> tables/social.connection.sql
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

-- >>> indexes/social.connection.sql
-- Indexes for social.connection. Each COMMENT names the query it serves (doc 05 section 6).
CREATE UNIQUE INDEX uq_connection__pair ON social.connection (user_low, user_high) WHERE deleted_at IS NULL;
COMMENT ON INDEX social.uq_connection__pair IS 'serves: UNIQUE: one relationship per pair; status lookups';

CREATE INDEX ix_connection__addressee_pending ON social.connection (addressee_id) WHERE status = 'pending' AND deleted_at IS NULL;
COMMENT ON INDEX social.ix_connection__addressee_pending IS 'serves: incoming connection requests';

CREATE INDEX ix_connection__requester_status ON social.connection (requester_id, status) WHERE deleted_at IS NULL;
COMMENT ON INDEX social.ix_connection__requester_status IS 'serves: my connections and sent requests';

CREATE INDEX ix_connection__addressee_status ON social.connection (addressee_id, status) WHERE deleted_at IS NULL;
COMMENT ON INDEX social.ix_connection__addressee_status IS 'serves: my connections (as addressee)';

-- >>> tables/social.user_block.sql
CREATE TABLE social.user_block (
    blocker_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
COMMENT ON TABLE social.user_block IS 'Blocks: the pair cannot find, connect, invite or mention each other';

-- >>> indexes/social.user_block.sql
-- Indexes for social.user_block. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_user_block__blocked ON social.user_block (blocked_id);
COMMENT ON INDEX social.ix_user_block__blocked IS 'serves: "hidden both ways" checks; FK';

-- >>> tables/social.care_circle.sql
CREATE TABLE social.care_circle (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    name common.safe_text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 50),
    wallpaper_code common.code REFERENCES ref.wallpaper (code),
    created_by_user uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    member_count smallint NOT NULL DEFAULT 0 CHECK (member_count BETWEEN 0 AND 50),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    created_by uuid,
    updated_by uuid,
    deleted_at timestamptz
);
COMMENT ON TABLE social.care_circle IS
'Care Circles; member_count = active members (kept by the procedures, doc 05 section 8)';

-- >>> indexes/social.care_circle.sql
-- Indexes for social.care_circle. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_care_circle__created_by_user ON social.care_circle (created_by_user);
COMMENT ON INDEX social.ix_care_circle__created_by_user IS 'serves: FK; cascade on account deletion';

CREATE INDEX ix_care_circle__wallpaper_code ON social.care_circle (wallpaper_code);
COMMENT ON INDEX social.ix_care_circle__wallpaper_code IS 'serves: FK to ref.wallpaper';

-- >>> tables/social.circle_member.sql
CREATE TABLE social.circle_member (
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    role common.code NOT NULL DEFAULT 'member' CHECK (role IN ('admin', 'member')),
    status common.code NOT NULL CHECK (
        status IN ('invited', 'active', 'declined', 'maybe_later', 'left', 'removed')
    ),
    invited_by uuid REFERENCES auth.user_account (id) ON DELETE SET NULL,
    invited_at timestamptz,
    joined_at timestamptz,
    left_at timestamptz,
    last_read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id),
    CHECK (status <> 'active' OR joined_at IS NOT NULL)
);
COMMENT ON TABLE social.circle_member IS
'Membership and invites; seats = active + invited + maybe_later (max 50, doc 06 section 7)';

-- >>> indexes/social.circle_member.sql
-- Indexes for social.circle_member. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_circle_member__user_status ON social.circle_member (user_id, status);
COMMENT ON INDEX social.ix_circle_member__user_status IS 'serves: Your Circles + pending invites; FK';

CREATE INDEX ix_circle_member__circle_status_joined ON social.circle_member (circle_id, status, joined_at);
COMMENT ON INDEX social.ix_circle_member__circle_status_joined IS
'serves: member list, seat count, admin succession (earliest joined)';

CREATE INDEX ix_circle_member__invited_by ON social.circle_member (invited_by);
COMMENT ON INDEX social.ix_circle_member__invited_by IS 'serves: FK; SET NULL on account deletion';

-- >>> tables/social.circle_share.sql
CREATE TABLE social.circle_share (
    circle_id uuid NOT NULL,
    user_id uuid NOT NULL,
    avatar_type common.code NOT NULL CHECK (avatar_type IN ('hydration', 'nutrition', 'sleep')),
    shared_since timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id, avatar_type),
    FOREIGN KEY (circle_id, user_id) REFERENCES social.circle_member (circle_id, user_id) ON DELETE CASCADE
);
COMMENT ON TABLE social.circle_share IS
'Avatars a member shares with a circle; ">= 1 share" is enforced by the procedures';

-- >>> indexes/social.circle_share.sql
-- Indexes for social.circle_share. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_circle_share__user_avatar ON social.circle_share (user_id, avatar_type);
COMMENT ON INDEX social.ix_circle_share__user_avatar IS 'serves: feed and visibility checks per owner';

-- >>> tables/social.circle_invite_link.sql
CREATE TABLE social.circle_invite_link (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    token_hash common.blind_index NOT NULL,
    created_by uuid REFERENCES auth.user_account (id) ON DELETE SET NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    max_uses smallint NOT NULL DEFAULT 49 CHECK (max_uses BETWEEN 1 AND 49),
    use_count smallint NOT NULL DEFAULT 0 CHECK (use_count >= 0),
    revoked_at timestamptz,
    CONSTRAINT uq_circle_invite_link__token_hash UNIQUE (token_hash),
    CHECK (use_count <= max_uses),
    CHECK (expires_at > created_at)
);
COMMENT ON TABLE social.circle_invite_link IS
'Circle invite links: SHA-256 of a 256-bit token (bearer secret), 7 days, max uses, revocable';

-- >>> indexes/social.circle_invite_link.sql
-- Indexes for social.circle_invite_link. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_circle_invite_link__circle ON social.circle_invite_link (circle_id, created_at DESC);
COMMENT ON INDEX social.ix_circle_invite_link__circle IS 'serves: FK; links per circle; daily creation limit';

CREATE INDEX ix_circle_invite_link__created_by ON social.circle_invite_link (created_by);
COMMENT ON INDEX social.ix_circle_invite_link__created_by IS 'serves: FK; SET NULL on account deletion';

-- >>> tables/social.chat_message.sql
CREATE TABLE social.chat_message (
    id uuid NOT NULL DEFAULT uuidv7(),
    created_at timestamptz NOT NULL DEFAULT now(),
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    sender_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    client_message_id uuid NOT NULL,
    body common.safe_text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
    deleted_at timestamptz,
    deleted_by uuid,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE social.chat_message IS
'Circle chat (plain text, no markup: common.safe_text); deleted messages keep the row, body hidden';

-- >>> indexes/social.chat_message.sql
-- Indexes for social.chat_message. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_chat_message__circle_time ON social.chat_message (circle_id, created_at DESC);
COMMENT ON INDEX social.ix_chat_message__circle_time IS 'serves: chat paging; unread counts; FK';

CREATE UNIQUE INDEX uq_chat_message__client_id ON social.chat_message (sender_id, client_message_id, created_at);
COMMENT ON INDEX social.uq_chat_message__client_id IS
'serves: UNIQUE: idempotent send (the procedure also checks the last day under a lock); FK';

-- >>> tables/social.chat_mention.sql
CREATE TABLE social.chat_mention (
    message_id uuid NOT NULL,
    mentioned_user_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    message_created_at timestamptz NOT NULL,
    circle_id uuid NOT NULL REFERENCES social.care_circle (id) ON DELETE CASCADE,
    PRIMARY KEY (message_id, mentioned_user_id),
    FOREIGN KEY (message_id, message_created_at) REFERENCES social.chat_message (id, created_at) ON DELETE CASCADE
);
COMMENT ON TABLE social.chat_mention IS '@mentions resolved to member user ids (never parsed from text)';

-- >>> indexes/social.chat_mention.sql
-- Indexes for social.chat_mention. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_chat_mention__user_time ON social.chat_mention (mentioned_user_id, message_created_at DESC);
COMMENT ON INDEX social.ix_chat_mention__user_time IS 'serves: my mentions; FK';

CREATE INDEX ix_chat_mention__message ON social.chat_mention (message_id, message_created_at);
COMMENT ON INDEX social.ix_chat_mention__message IS 'serves: FK to chat_message (cascade)';

CREATE INDEX ix_chat_mention__circle ON social.chat_mention (circle_id);
COMMENT ON INDEX social.ix_chat_mention__circle IS 'serves: FK; cascade on circle deletion';

-- >>> tables/social.activity_event.sql
CREATE TABLE social.activity_event (
    id uuid NOT NULL DEFAULT uuidv7(),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    actor_id uuid NOT NULL REFERENCES auth.user_account (id) ON DELETE CASCADE,
    event_type common.code NOT NULL CHECK (event_type IN ('logged', 'goal_completed', 'joined', 'left')),
    avatar_type common.code CHECK (avatar_type IN ('hydration', 'nutrition', 'sleep')),
    circle_id uuid REFERENCES social.care_circle (id) ON DELETE CASCADE,
    summary jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(summary) = 'object' AND pg_column_size(summary) < 1024),
    PRIMARY KEY (id, occurred_at),
    -- Avatar events belong to the actor (shown in every circle they share that avatar with);
    -- membership events belong to one circle.
    CHECK (
        (event_type IN ('logged', 'goal_completed') AND avatar_type IS NOT NULL AND circle_id IS NULL)
        OR (event_type IN ('joined', 'left') AND avatar_type IS NULL AND circle_id IS NOT NULL)
    )
) PARTITION BY RANGE (occurred_at);
COMMENT ON TABLE social.activity_event IS
'Recent Updates source (fan-out-on-read): summary holds display values only, never free text';

-- >>> indexes/social.activity_event.sql
-- Indexes for social.activity_event. Each COMMENT names the query it serves (doc 05 section 6).
CREATE INDEX ix_activity_event__actor_avatar_time ON social.activity_event (actor_id, avatar_type, occurred_at DESC);
COMMENT ON INDEX social.ix_activity_event__actor_avatar_time IS 'serves: circle feed (fan-out-on-read); FK';

CREATE INDEX ix_activity_event__circle_time ON social.activity_event (circle_id, occurred_at DESC) WHERE circle_id IS NOT NULL;
COMMENT ON INDEX social.ix_activity_event__circle_time IS 'serves: join/leave events in the circle feed; FK';

-- >>> tables/notify.circle_notification_preference.sql
CREATE TABLE notify.circle_notification_preference (
    circle_id uuid NOT NULL,
    user_id uuid NOT NULL,
    member_join_leave boolean NOT NULL DEFAULT TRUE,
    circle_updates boolean NOT NULL DEFAULT TRUE,
    goal_completions boolean NOT NULL DEFAULT TRUE,
    avatar_updates boolean NOT NULL DEFAULT FALSE,
    mentions boolean NOT NULL DEFAULT TRUE,
    new_messages boolean NOT NULL DEFAULT FALSE,
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (circle_id, user_id),
    FOREIGN KEY (circle_id, user_id) REFERENCES social.circle_member (circle_id, user_id) ON DELETE CASCADE
);
COMMENT ON TABLE notify.circle_notification_preference IS
'Per-circle notification switches (Figma circle Notification Settings); no row = defaults';

-- >>> indexes/notify.notification_circle.sql
-- Session 12: circle filter for the in-app notification list (GET /notifications?circle_id=).
CREATE INDEX ix_notification__user_circle_time ON notify.notification (user_id, circle_id, created_at DESC) WHERE circle_id IS NOT NULL;
COMMENT ON INDEX notify.ix_notification__user_circle_time IS 'serves: circle notifications list';

-- >>> tables/_social_partitions.sql
-- Monthly RANGE partitions for the social tables (Session 12), same scheme as
-- tables/_initial_partitions.sql: a DEFAULT partition plus the current UTC month through
-- +premake_months; ops.pr_ensure_partitions keeps creating future months. Chat lives as long as its
-- circle (doc 05 section 9, OQ-48); feed events are kept 13 months (the feed shows recent days).

INSERT INTO ops.partition_config (parent_table, bound_type, premake_months, retention_months) VALUES
('social.activity_event', 'timestamptz', 3, 13),
('social.chat_message', 'timestamptz', 3, NULL)
ON CONFLICT (parent_table) DO NOTHING;

DO $partitions$
DECLARE
    cfg record;
    m integer;
    month_start date;
    parent_schema text;
    parent_name text;
    lo text;
    hi text;
BEGIN
    FOR cfg IN SELECT * FROM ops.partition_config WHERE parent_table LIKE 'social.%' ORDER BY parent_table LOOP
        parent_schema := split_part(cfg.parent_table, '.', 1);
        parent_name := split_part(cfg.parent_table, '.', 2);

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I DEFAULT',
            parent_schema, parent_name || '_default', parent_schema, parent_name
        );

        FOR m IN 0..cfg.premake_months LOOP
            month_start := (date_trunc('month', now() AT TIME ZONE 'UTC') + make_interval(months => m))::date;
            lo := to_char(month_start, 'YYYY-MM-DD');
            hi := to_char((month_start + interval '1 month')::date, 'YYYY-MM-DD');
            IF cfg.bound_type = 'timestamptz' THEN
                lo := lo || ' 00:00:00+00';
                hi := hi || ' 00:00:00+00';
            END IF;
            EXECUTE format(
                'CREATE TABLE IF NOT EXISTS %I.%I PARTITION OF %I.%I FOR VALUES FROM (%L) TO (%L)',
                parent_schema, parent_name || '_p' || to_char(month_start, 'YYYY_MM'),
                parent_schema, parent_name, lo, hi
            );
        END LOOP;
    END LOOP;
END
$partitions$;

-- >>> roles/021_rls_social.sql
-- Row-Level Security for the social tables (Session 12; doc 05 section 7, doc 07 SEC-4.4).
-- Membership-based: a policy asks a helper "is the current user an active member of this circle?".
-- The helpers are owned by migration_owner (the table owner, which RLS does not apply to) so a
-- policy on circle_member can look at circle_member without recursing into itself. They read only
-- the current user's own membership rows and return a boolean.

CREATE OR REPLACE FUNCTION social.fn_is_active_member(p_circle_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id
          AND m.user_id = common.current_user_id()
          AND m.status = 'active'
    )
$$;
COMMENT ON FUNCTION social.fn_is_active_member(uuid) IS 'RLS helper: the current user is an active member';

CREATE OR REPLACE FUNCTION social.fn_can_see_circle(p_circle_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1 FROM social.circle_member AS m
        WHERE m.circle_id = p_circle_id
          AND m.user_id = common.current_user_id()
          AND m.status IN ('invited', 'active', 'maybe_later')
    )
$$;
COMMENT ON FUNCTION social.fn_can_see_circle(uuid) IS
'RLS helper: the current user is an active member or has an open invite';

CREATE OR REPLACE FUNCTION social.fn_shares_with_me(p_actor_id uuid, p_avatar_type text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM social.circle_share AS s
        INNER JOIN social.circle_member AS owner
            ON owner.circle_id = s.circle_id AND owner.user_id = s.user_id AND owner.status = 'active'
        INNER JOIN social.circle_member AS viewer
            ON viewer.circle_id = s.circle_id AND viewer.user_id = common.current_user_id()
               AND viewer.status = 'active'
        WHERE s.user_id = p_actor_id AND s.avatar_type = p_avatar_type
    )
$$;
COMMENT ON FUNCTION social.fn_shares_with_me(uuid, text) IS
'RLS helper: the actor shares this avatar with a circle the current user is active in';

REVOKE ALL ON FUNCTION social.fn_is_active_member(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_can_see_circle(uuid) FROM public;
REVOKE ALL ON FUNCTION social.fn_shares_with_me(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION social.fn_is_active_member(uuid) TO api_definer;
GRANT EXECUTE ON FUNCTION social.fn_can_see_circle(uuid) TO api_definer;
GRANT EXECUTE ON FUNCTION social.fn_shares_with_me(uuid, text) TO api_definer;

ALTER TABLE social.connection ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_pairs ON social.connection TO api_definer
USING (common.current_user_id() IN (requester_id, addressee_id))
WITH CHECK (common.current_user_id() IN (requester_id, addressee_id));

ALTER TABLE social.user_block ENABLE ROW LEVEL SECURITY;
CREATE POLICY either_side ON social.user_block TO api_definer
USING (common.current_user_id() IN (blocker_id, blocked_id))
WITH CHECK (blocker_id = common.current_user_id());

ALTER TABLE social.care_circle ENABLE ROW LEVEL SECURITY;
CREATE POLICY members ON social.care_circle TO api_definer
USING (social.fn_can_see_circle(id) OR created_by_user = common.current_user_id())
WITH CHECK (social.fn_can_see_circle(id) OR created_by_user = common.current_user_id());

ALTER TABLE social.circle_member ENABLE ROW LEVEL SECURITY;
CREATE POLICY members ON social.circle_member TO api_definer
USING (user_id = common.current_user_id() OR social.fn_is_active_member(circle_id))
WITH CHECK (user_id = common.current_user_id() OR social.fn_is_active_member(circle_id));

ALTER TABLE social.circle_share ENABLE ROW LEVEL SECURITY;
CREATE POLICY members ON social.circle_share TO api_definer
USING (user_id = common.current_user_id() OR social.fn_is_active_member(circle_id))
WITH CHECK (user_id = common.current_user_id());

-- Resolving a link happens before the caller is a member; rows hold only the token hash, and the
-- only lookup is by that hash (a 256-bit secret), so reading is open and writing needs membership.
ALTER TABLE social.circle_invite_link ENABLE ROW LEVEL SECURITY;
CREATE POLICY read_by_hash ON social.circle_invite_link FOR SELECT TO api_definer USING (TRUE);
CREATE POLICY members_write ON social.circle_invite_link FOR INSERT TO api_definer
WITH CHECK (social.fn_is_active_member(circle_id));
CREATE POLICY members_update ON social.circle_invite_link FOR UPDATE TO api_definer
USING (TRUE) WITH CHECK (TRUE);

ALTER TABLE social.chat_message ENABLE ROW LEVEL SECURITY;
CREATE POLICY members_read ON social.chat_message FOR SELECT TO api_definer
USING (social.fn_is_active_member(circle_id));
CREATE POLICY sender_insert ON social.chat_message FOR INSERT TO api_definer
WITH CHECK (sender_id = common.current_user_id() AND social.fn_is_active_member(circle_id));
CREATE POLICY members_update ON social.chat_message FOR UPDATE TO api_definer
USING (social.fn_is_active_member(circle_id))
WITH CHECK (social.fn_is_active_member(circle_id));

ALTER TABLE social.chat_mention ENABLE ROW LEVEL SECURITY;
CREATE POLICY members ON social.chat_mention TO api_definer
USING (mentioned_user_id = common.current_user_id() OR social.fn_is_active_member(circle_id))
WITH CHECK (social.fn_is_active_member(circle_id));

ALTER TABLE social.activity_event ENABLE ROW LEVEL SECURITY;
CREATE POLICY visible ON social.activity_event FOR SELECT TO api_definer
USING (
    actor_id = common.current_user_id()
    OR (circle_id IS NOT NULL AND social.fn_is_active_member(circle_id))
    OR (avatar_type IS NOT NULL AND social.fn_shares_with_me(actor_id, avatar_type))
);
CREATE POLICY own_insert ON social.activity_event FOR INSERT TO api_definer
WITH CHECK (actor_id = common.current_user_id());

ALTER TABLE notify.circle_notification_preference ENABLE ROW LEVEL SECURITY;
CREATE POLICY own_rows ON notify.circle_notification_preference TO api_definer
USING (user_id = common.current_user_id())
WITH CHECK (user_id = common.current_user_id());
