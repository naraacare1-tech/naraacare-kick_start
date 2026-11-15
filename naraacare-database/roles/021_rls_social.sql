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
