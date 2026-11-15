-- Help & Support writes (Session 14, doc 04 section 2.13, OQ-51).
--   * pr_create_ticket: Report a problem. Plain text (common.safe_text, 1-2000); the optional screenshot
--     was already checked, re-encoded and stored by the API under a random key (support/<uuid>.png|jpg).
--     Returns a short reference (NC-XXXXXXXX) for the user.
--   * pr_create_feature_request: Request a feature (title 1-120, benefit 1-1000).
--   Each is limited to 5 per 24 hours per user (SUPPORT_LIMIT_REACHED, 429).
-- Worker (ops, owned by migration_owner, app_worker only: procedures/R__32_ops.reports_support.sql):
--   * fn_support_unforwarded: tickets and requests not yet emailed to the support inbox, with the
--     account email so support can reply. The email template escapes every value.
--   * pr_mark_support_forwarded: forwarded (or one more failed attempt; gives up after 20).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE support.pr_create_ticket(
    p_user_id uuid,
    p_category text,
    p_description common.safe_text,
    p_screenshot_key common.object_key DEFAULT NULL,
    INOUT o_ticket_id uuid DEFAULT NULL,
    INOUT o_ticket_ref text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF (
        SELECT count(*) FROM support.ticket AS t
        WHERE t.user_id = p_user_id AND t.created_at > now() - interval '24 hours'
    ) >= 5 THEN
        RAISE EXCEPTION 'ticket limit' USING ERRCODE = 'P0001', DETAIL = 'SUPPORT_LIMIT_REACHED';
    END IF;
    o_ticket_ref := 'NC-' || upper(left(replace(uuidv4()::text, '-', ''), 8));
    INSERT INTO support.ticket (user_id, ticket_ref, category, description, screenshot_key)
    VALUES (p_user_id, o_ticket_ref, p_category, btrim(p_description), p_screenshot_key)
    RETURNING id INTO o_ticket_id;
END
$$;

CREATE OR REPLACE PROCEDURE support.pr_create_feature_request(
    p_user_id uuid,
    p_title common.safe_text,
    p_benefit common.safe_text,
    INOUT o_request_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    IF (
        SELECT count(*) FROM support.feature_request AS f
        WHERE f.user_id = p_user_id AND f.created_at > now() - interval '24 hours'
    ) >= 5 THEN
        RAISE EXCEPTION 'request limit' USING ERRCODE = 'P0001', DETAIL = 'SUPPORT_LIMIT_REACHED';
    END IF;
    INSERT INTO support.feature_request (user_id, title, benefit)
    VALUES (p_user_id, btrim(p_title), btrim(p_benefit))
    RETURNING id INTO o_request_id;
END
$$;

COMMENT ON PROCEDURE support.pr_create_ticket(uuid, text, common.safe_text, common.object_key, uuid, text) IS
'POST /support/tickets: store a problem report (5 per 24 h) and return its reference';
COMMENT ON PROCEDURE support.pr_create_feature_request(uuid, common.safe_text, common.safe_text, uuid) IS
'POST /support/feature-requests: store a feature request (5 per 24 h)';

REVOKE ALL ON PROCEDURE support.pr_create_ticket(uuid, text, common.safe_text, common.object_key, uuid, text) FROM public;
REVOKE ALL ON PROCEDURE support.pr_create_feature_request(uuid, common.safe_text, common.safe_text, uuid) FROM public;
GRANT EXECUTE ON PROCEDURE support.pr_create_ticket(uuid, text, common.safe_text, common.object_key, uuid, text) TO app_rw;
GRANT EXECUTE ON PROCEDURE support.pr_create_feature_request(uuid, common.safe_text, common.safe_text, uuid)
TO app_rw;
