-- In-app notification list (doc 04 section 2.7 / 2.9, Session 12). Rows hold a template code and
-- params (codes, ids, numbers only); the app writes the text. RLS (own_rows) limits every statement
-- here to the caller's own rows.
--   * fn_notifications: newest first, optional circle filter (circle Notifications screen), keyset by
--     created_at.
--   * pr_mark_notifications_read: given ids, or all of one circle, or all.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION notify.fn_notifications(
    p_user_id uuid, p_circle_id uuid DEFAULT NULL, p_before timestamptz DEFAULT NULL, p_limit integer DEFAULT 30
)
RETURNS TABLE (
    notification_id uuid,
    created_at timestamptz,
    circle_id uuid,
    category common.code,
    template_code common.code,
    params jsonb,
    deep_link common.deep_link,
    read_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF p_circle_id IS NOT NULL THEN
        PERFORM social.fn_require_member(p_circle_id, p_user_id);
    END IF;
    RETURN QUERY
    SELECT n.id, n.created_at, n.circle_id, n.category, n.template_code, n.params, n.deep_link, n.read_at
    FROM notify.notification AS n
    WHERE n.user_id = p_user_id
      AND (p_circle_id IS NULL OR n.circle_id = p_circle_id)
      AND (p_before IS NULL OR n.created_at < p_before)
      AND n.created_at > now() - interval '90 days'
    ORDER BY n.created_at DESC
    LIMIT least(greatest(coalesce(p_limit, 30), 1), 50);
END
$$;

CREATE OR REPLACE PROCEDURE notify.pr_mark_notifications_read(
    p_user_id uuid, p_circle_id uuid DEFAULT NULL, p_ids uuid[] DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF cardinality(p_ids) > 100 THEN
        RAISE EXCEPTION 'at most 100 ids' USING ERRCODE = '22023', DETAIL = 'INVALID_ARGUMENT';
    END IF;
    UPDATE notify.notification SET read_at = now()
    WHERE user_id = p_user_id AND read_at IS NULL
      AND (p_circle_id IS NULL OR circle_id = p_circle_id)
      AND (p_ids IS NULL OR id = ANY (p_ids))
      AND created_at > now() - interval '90 days';
END
$$;

COMMENT ON FUNCTION notify.fn_notifications(uuid, uuid, timestamptz, integer) IS
'The caller''s in-app notifications, newest first, optional circle filter (keyset by time)';
COMMENT ON PROCEDURE notify.pr_mark_notifications_read(uuid, uuid, uuid[]) IS
'Mark the caller''s notifications read (ids, one circle, or all)';

REVOKE ALL ON FUNCTION notify.fn_notifications(uuid, uuid, timestamptz, integer) FROM public;
REVOKE ALL ON PROCEDURE notify.pr_mark_notifications_read(uuid, uuid, uuid[]) FROM public;
GRANT EXECUTE ON FUNCTION notify.fn_notifications(uuid, uuid, timestamptz, integer) TO app_rw;
GRANT EXECUTE ON PROCEDURE notify.pr_mark_notifications_read(uuid, uuid, uuid[]) TO app_rw;
