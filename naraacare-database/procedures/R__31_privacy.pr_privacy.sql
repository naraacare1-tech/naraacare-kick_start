-- Privacy centre, export and deletion requests for the API (Session 15, doc 04 section 2.13, doc 07 SEC-7).
--   * fn_privacy_status: one call at launch -> scheduled deletion (if any), policies that need fresh
--     consent (the latest published Terms / Privacy policy has a higher major version than the one the
--     user accepted; drafts never trigger it) and the latest export.
--   * fn_exports: GET /privacy/exports/{id} (own rows only).
--   * pr_request_export: idempotent by (user, Idempotency-Key); 1 per 24 h (EXPORT_LIMIT_REACHED).
--     The API re-authenticates the user first (password or email code).
--   * pr_request_deletion: 30-day grace (OQ-47); revokes every session and push token at once. The
--     account stays active so the user can sign in during the grace period and cancel.
--   * pr_cancel_deletion: back to normal (the user signs in again on each device).
-- Errors: 42501 not found (404); P0001 EXPORT_LIMIT_REACHED; 22023 INVALID_ARGUMENT.
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE FUNCTION privacy.fn_privacy_status(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_result jsonb;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    WITH accepted AS (
        SELECT DISTINCT ON (c.purpose) c.purpose, c.policy_version, c.granted
        FROM privacy.consent_record AS c
        WHERE c.user_id = p_user_id AND c.purpose IN ('terms', 'privacy')
        ORDER BY c.purpose, c.recorded_at DESC, c.id DESC
    ),
    current_docs AS (
        SELECT DISTINCT ON (d.doc_type) d.doc_type, d.version, d.url
        FROM ref.policy_document AS d
        WHERE d.doc_type IN ('terms', 'privacy') AND d.published_at IS NOT NULL AND d.published_at <= now()
        ORDER BY d.doc_type, d.published_at DESC, d.id DESC
    ),
    reconsent AS (
        SELECT coalesce(jsonb_agg(jsonb_build_object(
            'doc_type', cd.doc_type, 'accepted_version', a.policy_version,
            'current_version', cd.version, 'url', cd.url
        ) ORDER BY cd.doc_type), '[]'::jsonb) AS items
        FROM current_docs AS cd
        LEFT JOIN accepted AS a ON a.purpose = cd.doc_type
        WHERE a.policy_version IS NULL OR NOT a.granted
           OR split_part(cd.version, '.', 1) ~ '^[0-9]+$'
              AND split_part(coalesce(a.policy_version, '0'), '.', 1) ~ '^[0-9]+$'
              AND split_part(cd.version, '.', 1)::integer > split_part(a.policy_version, '.', 1)::integer
    )
    SELECT jsonb_build_object(
        'deletion', (
            SELECT jsonb_build_object('requested_at', r.requested_at, 'scheduled_for', r.scheduled_for)
            FROM privacy.deletion_request AS r
            WHERE r.user_id = p_user_id AND r.status = 'scheduled'
            ORDER BY r.requested_at DESC LIMIT 1
        ),
        'reconsent', (SELECT items FROM reconsent),
        'latest_export', (
            SELECT jsonb_build_object(
                'export_id', e.id, 'status',
                CASE WHEN e.status = 'ready' AND e.expires_at <= now() THEN 'expired' ELSE e.status END,
                'requested_at', e.requested_at, 'expires_at', e.expires_at, 'size_bytes', e.size_bytes
            )
            FROM privacy.export_request AS e
            WHERE e.user_id = p_user_id
            ORDER BY e.requested_at DESC LIMIT 1
        )
    ) INTO v_result;
    RETURN v_result;
END
$$;

CREATE OR REPLACE FUNCTION privacy.fn_exports(p_user_id uuid, p_export_id uuid)
RETURNS TABLE (
    export_id uuid,
    status common.code,
    requested_at timestamptz,
    ready_at timestamptz,
    expires_at timestamptz,
    size_bytes bigint,
    object_key common.object_key
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    RETURN QUERY
    SELECT
        e.id,
        CASE WHEN e.status = 'ready' AND e.expires_at <= now() THEN 'expired'::common.code ELSE e.status END,
        e.requested_at, e.ready_at, e.expires_at, e.size_bytes,
        CASE WHEN e.status = 'ready' AND e.expires_at > now() THEN e.object_key END::common.object_key
    FROM privacy.export_request AS e
    WHERE e.user_id = p_user_id AND e.id = p_export_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'export not found' USING ERRCODE = '42501';
    END IF;
END
$$;

CREATE OR REPLACE PROCEDURE privacy.pr_request_export(
    p_user_id uuid,
    p_idempotency_key uuid,
    INOUT o_export_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL,
    INOUT o_created boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT e.id, e.status INTO o_export_id, o_status
    FROM privacy.export_request AS e
    WHERE e.user_id = p_user_id AND e.idempotency_key = p_idempotency_key;
    IF FOUND THEN
        o_created := FALSE;
        RETURN;
    END IF;
    IF EXISTS (
        SELECT 1 FROM privacy.export_request AS e
        WHERE e.user_id = p_user_id AND e.requested_at > now() - interval '24 hours' AND e.status <> 'failed'
    ) THEN
        RAISE EXCEPTION 'one export per day' USING ERRCODE = 'P0001', DETAIL = 'EXPORT_LIMIT_REACHED';
    END IF;
    INSERT INTO privacy.export_request (user_id, idempotency_key)
    VALUES (p_user_id, p_idempotency_key)
    RETURNING id, status INTO o_export_id, o_status;
    o_created := TRUE;
END
$$;

CREATE OR REPLACE PROCEDURE privacy.pr_request_deletion(
    p_user_id uuid,
    INOUT o_scheduled_for timestamptz DEFAULT NULL,
    INOUT o_created boolean DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_revoked integer;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT r.scheduled_for INTO o_scheduled_for
    FROM privacy.deletion_request AS r
    WHERE r.user_id = p_user_id AND r.status = 'scheduled';
    IF FOUND THEN
        o_created := FALSE;
        RETURN;
    END IF;
    INSERT INTO privacy.deletion_request (user_id, scheduled_for)
    VALUES (p_user_id, now() + interval '30 days')
    RETURNING scheduled_for INTO o_scheduled_for;
    o_created := TRUE;
    CALL auth.pr_revoke_tokens(p_user_id, 'all', 'deletion', NULL, NULL, v_revoked);
    UPDATE notify.device SET push_token = NULL, revoked_at = coalesce(revoked_at, now())
    WHERE user_id = p_user_id;
END
$$;

CREATE OR REPLACE PROCEDURE privacy.pr_cancel_deletion(p_user_id uuid, INOUT o_cancelled boolean DEFAULT NULL)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    UPDATE privacy.deletion_request SET status = 'cancelled', cancelled_at = now()
    WHERE user_id = p_user_id AND status = 'scheduled';
    o_cancelled := FOUND;
END
$$;

COMMENT ON FUNCTION privacy.fn_privacy_status(uuid) IS
'GET /privacy/status: scheduled deletion, policies needing fresh consent, latest export';
COMMENT ON FUNCTION privacy.fn_exports(uuid, uuid) IS 'GET /privacy/exports/{id}: one of the caller''s exports';
COMMENT ON PROCEDURE privacy.pr_request_export(uuid, uuid, uuid, text, boolean) IS
'POST /privacy/exports: queue a data export (idempotent, 1 per 24 h)';
COMMENT ON PROCEDURE privacy.pr_request_deletion(uuid, timestamptz, boolean) IS
'POST /privacy/deletion-request: schedule erasure in 30 days, revoke sessions and push tokens';
COMMENT ON PROCEDURE privacy.pr_cancel_deletion(uuid, boolean) IS
'DELETE /privacy/deletion-request: cancel a scheduled deletion during the grace period';

REVOKE ALL ON FUNCTION privacy.fn_privacy_status(uuid) FROM public;
REVOKE ALL ON FUNCTION privacy.fn_exports(uuid, uuid) FROM public;
REVOKE ALL ON PROCEDURE privacy.pr_request_export(uuid, uuid, uuid, text, boolean) FROM public;
REVOKE ALL ON PROCEDURE privacy.pr_request_deletion(uuid, timestamptz, boolean) FROM public;
REVOKE ALL ON PROCEDURE privacy.pr_cancel_deletion(uuid, boolean) FROM public;
GRANT EXECUTE ON FUNCTION privacy.fn_privacy_status(uuid) TO app_rw;
GRANT EXECUTE ON FUNCTION privacy.fn_exports(uuid, uuid) TO app_rw;
GRANT EXECUTE ON PROCEDURE privacy.pr_request_export(uuid, uuid, uuid, text, boolean) TO app_rw;
GRANT EXECUTE ON PROCEDURE privacy.pr_request_deletion(uuid, timestamptz, boolean) TO app_rw;
GRANT EXECUTE ON PROCEDURE privacy.pr_cancel_deletion(uuid, boolean) TO app_rw;
