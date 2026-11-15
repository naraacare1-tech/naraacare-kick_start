-- Privacy workers (Session 15, doc 07 SEC-7, doc 05 section 9). Cross-user routines, so they live in ops:
-- owned by migration_owner (table owner: RLS does not apply) and granted only to app_worker. They take
-- only ids from the worker, never user text.
--
-- Export (right to access)
--   * fn_claim_exports: queued (or stuck) export requests, SKIP LOCKED, marked running.
--   * fn_export_user: every row the user owns, as JSON keyed by "schema.table". Driven by the catalog:
--     any table with a user column (user_id, sender_id, requester_id, ...) is included automatically, so
--     a new table cannot be forgotten. Secrets are never exported (columns ending in _hash, tokens,
--     codes) and neither are tables that only hold them (refresh tokens, password history, OTPs).
--   * pr_finish_export / fn_expire_exports: ready for 7 days (+ "export ready" notification) or failed.
--
-- Erasure (right to erasure, 30-day grace, OQ-47)
--   * fn_due_deletions: scheduled deletions whose grace period is over, with the address for the
--     receipt and the Apple refresh token to revoke (read just before erasure, never logged).
--   * fn_user_files: storage keys to delete (reports, support screenshots, exports).
--   * pr_mark_deletion_receipt: the receipt was sent (so a retried run does not send it twice).
--   * pr_delete_user: archives consent proof and store transactions with the user id hashed (doc 05
--     section 9: 8 years), hands circles the user created to the earliest-joined remaining member,
--     removes the user's id from other people's rows (authorship columns, notification params), deletes
--     the account (every personal row cascades), then removes personal values from the audit trail
--     (including the rows this delete just wrote) and logs a hashed deletion record.
--
-- Retention (doc 05 section 9, OQ-48 pending legal approval; partitions are handled by
-- ops.pr_apply_retention)
--   * fn_apply_row_retention: purges rows past privacy.retention_policy (deleted chat messages, inactive
--     Rin chats, token usage, archives) and returns the counts per item (monitoring metric).
--   * fn_expired_attachments: support screenshots past retention: clears the key, returns it for deletion.

CREATE OR REPLACE FUNCTION ops.fn_claim_exports(p_limit integer DEFAULT 3)
RETURNS TABLE (export_id uuid, user_id uuid, attempts smallint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH picked AS (
        SELECT e.id FROM privacy.export_request AS e
        WHERE e.status = 'queued' OR (e.status = 'running' AND e.started_at < now() - interval '30 minutes')
        ORDER BY e.requested_at
        LIMIT least(greatest(coalesce(p_limit, 3), 1), 10)
        FOR UPDATE SKIP LOCKED
    )
    UPDATE privacy.export_request AS e
    SET status = 'running', started_at = now(), attempts = e.attempts + 1
    FROM picked
    WHERE e.id = picked.id
    RETURNING e.id, e.user_id, e.attempts;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_export_user(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    t record;
    v_rows jsonb;
    v_result jsonb := '{}'::jsonb;
BEGIN
    SELECT coalesce(jsonb_agg(to_jsonb(a) - 'password_hash'), '[]'::jsonb) INTO v_rows
    FROM auth.user_account AS a WHERE a.id = p_user_id;
    v_result := jsonb_build_object('auth.user_account', v_rows);

    FOR t IN
        SELECT n.nspname AS schema_name, c.relname AS table_name,
               string_agg(format('%I = $1', a.attname), ' OR ' ORDER BY a.attname) AS predicate,
               (
                   SELECT coalesce(array_agg(s.attname::text), '{}')
                   FROM pg_catalog.pg_attribute AS s
                   WHERE s.attrelid = c.oid AND s.attnum > 0 AND NOT s.attisdropped
                     AND (s.attname ~ '(_hash|token|^code)$' OR s.attname ~ 'token')
               ) AS secret_columns
        FROM pg_catalog.pg_class AS c
        INNER JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        INNER JOIN pg_catalog.pg_attribute AS a
            ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
           AND a.attname IN (
               'user_id', 'sender_id', 'requester_id', 'addressee_id', 'blocker_id', 'blocked_id',
               'created_by_user', 'referrer_id', 'referred_user_id', 'actor_id', 'mentioned_user_id'
           )
        WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition
          AND n.nspname IN (
              'app', 'activity', 'nutrition', 'hydration', 'sleep', 'billing', 'notify', 'privacy',
              'social', 'ai', 'report', 'support', 'auth'
          )
          AND (n.nspname, c.relname) NOT IN (
              ('auth', 'refresh_token'), ('auth', 'password_history'), ('auth', 'otp_challenge')
          )
        GROUP BY n.nspname, c.relname, c.oid
        ORDER BY n.nspname, c.relname
    LOOP
        EXECUTE format(
            'SELECT coalesce(jsonb_agg(to_jsonb(x) - %L::text[]), ''[]''::jsonb) FROM %I.%I AS x WHERE %s',
            t.secret_columns, t.schema_name, t.table_name, t.predicate
        ) INTO v_rows USING p_user_id;
        v_result := v_result || jsonb_build_object(t.schema_name || '.' || t.table_name, v_rows);
    END LOOP;
    RETURN v_result;
END
$$;

CREATE OR REPLACE PROCEDURE ops.pr_finish_export(
    p_export_id uuid,
    p_ok boolean,
    p_object_key text DEFAULT NULL,
    p_size_bytes bigint DEFAULT NULL,
    p_error_code text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_user uuid;
    v_attempts smallint;
BEGIN
    SELECT e.user_id, e.attempts INTO v_user, v_attempts
    FROM privacy.export_request AS e WHERE e.id = p_export_id AND e.status = 'running' FOR UPDATE;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    IF p_ok THEN
        UPDATE privacy.export_request SET
            status = 'ready', object_key = p_object_key, size_bytes = p_size_bytes, ready_at = now(),
            expires_at = now() + interval '7 days', error_code = NULL
        WHERE id = p_export_id;
        INSERT INTO notify.notification (user_id, category, template_code, params, deep_link)
        VALUES (v_user, 'privacy', 'export_ready', jsonb_build_object('export_id', p_export_id),
                'naraacare://profile/privacy');
    ELSIF v_attempts < 3 THEN
        UPDATE privacy.export_request SET status = 'queued', error_code = p_error_code WHERE id = p_export_id;
    ELSE
        UPDATE privacy.export_request SET status = 'failed', error_code = p_error_code WHERE id = p_export_id;
    END IF;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_expire_exports(p_limit integer DEFAULT 500)
RETURNS TABLE (export_id uuid, object_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH due AS (
        SELECT e.id FROM privacy.export_request AS e
        WHERE e.status = 'ready' AND e.expires_at <= now()
        ORDER BY e.expires_at
        LIMIT least(greatest(coalesce(p_limit, 500), 1), 5000)
        FOR UPDATE SKIP LOCKED
    )
    UPDATE privacy.export_request AS e SET status = 'expired'
    FROM due WHERE e.id = due.id
    RETURNING e.id, e.object_key::text;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_due_deletions(p_limit integer DEFAULT 20)
RETURNS TABLE (
    user_id uuid,
    email text,
    requested_at timestamptz,
    receipt_sent boolean,
    apple_refresh_token text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT r.user_id, a.email::text, r.requested_at, r.receipt_sent_at IS NOT NULL,
           (
               SELECT l.provider_refresh_token::text FROM auth.identity_link AS l
               WHERE l.user_id = r.user_id AND l.provider = 'apple' AND l.provider_refresh_token IS NOT NULL
               LIMIT 1
           )
    FROM privacy.deletion_request AS r
    INNER JOIN auth.user_account AS a ON a.id = r.user_id
    WHERE r.status = 'scheduled' AND r.scheduled_for <= now()
    ORDER BY r.scheduled_for
    LIMIT least(greatest(coalesce(p_limit, 20), 1), 200);
$$;

CREATE OR REPLACE FUNCTION ops.fn_user_files(p_user_id uuid)
RETURNS TABLE (object_key text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT j.storage_key::text FROM report.report_job AS j
    WHERE j.user_id = p_user_id AND j.storage_key IS NOT NULL
    UNION
    SELECT t.screenshot_key::text FROM support.ticket AS t
    WHERE t.user_id = p_user_id AND t.screenshot_key IS NOT NULL
    UNION
    SELECT e.object_key::text FROM privacy.export_request AS e
    WHERE e.user_id = p_user_id AND e.object_key IS NOT NULL;
$$;

CREATE OR REPLACE PROCEDURE ops.pr_mark_deletion_receipt(p_user_id uuid)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    UPDATE privacy.deletion_request SET receipt_sent_at = now()
    WHERE user_id = p_user_id AND status = 'scheduled' AND receipt_sent_at IS NULL;
$$;

CREATE OR REPLACE PROCEDURE ops.pr_delete_user(p_user_id uuid, INOUT o_archived integer DEFAULT NULL)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_hash text := encode(sha256(convert_to(p_user_id::text, 'UTF8')), 'hex');
    v_requested timestamptz;
    v_count integer;
    v_text text := p_user_id::text;
    c record;
    v_successor uuid;
BEGIN
    SELECT r.requested_at INTO v_requested
    FROM privacy.deletion_request AS r
    WHERE r.user_id = p_user_id AND r.status = 'scheduled' AND r.scheduled_for <= now()
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'no due deletion for this user' USING ERRCODE = '22023', DETAIL = 'NOT_DUE';
    END IF;
    PERFORM set_config('lock_timeout', '10s', true);
    -- The erasure has no actor: audit rows it writes must not name the user.
    PERFORM set_config('app.user_id', '', true);

    -- 1. Archives (doc 05 section 9): consent proof and store transactions, user id hashed.
    INSERT INTO privacy.consent_archive (user_hash, purpose, policy_version, granted, recorded_at)
    SELECT v_hash, c2.purpose, c2.policy_version, c2.granted, c2.recorded_at
    FROM privacy.consent_record AS c2 WHERE c2.user_id = p_user_id;
    GET DIAGNOSTICS o_archived = ROW_COUNT;
    INSERT INTO billing.transaction_archive (
        user_hash, platform, product_id, store_transaction_id, type, amount_micros, currency, occurred_at
    )
    SELECT v_hash, s.platform, s.product_id, t.store_transaction_id, t.type, t.amount_micros, t.currency,
           t.occurred_at
    FROM billing.store_transaction AS t
    INNER JOIN billing.subscription AS s ON s.id = t.subscription_id
    WHERE s.user_id = p_user_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    o_archived := o_archived + v_count;

    -- 2. Circles the user created: hand them to the earliest-joined other active member (admin if
    --    the circle has no other admin). Circles with nobody else go away with the account.
    FOR c IN
        SELECT cc.id FROM social.care_circle AS cc
        WHERE cc.created_by_user = p_user_id AND cc.deleted_at IS NULL
    LOOP
        SELECT m.user_id INTO v_successor
        FROM social.circle_member AS m
        WHERE m.circle_id = c.id AND m.user_id <> p_user_id AND m.status = 'active'
        ORDER BY (m.role = 'admin') DESC, m.joined_at, m.user_id
        LIMIT 1;
        IF v_successor IS NOT NULL THEN
            UPDATE social.care_circle SET created_by_user = v_successor, updated_at = now() WHERE id = c.id;
            UPDATE social.circle_member SET role = 'admin'
            WHERE circle_id = c.id AND user_id = v_successor
              AND NOT EXISTS (
                  SELECT 1 FROM social.circle_member AS o
                  WHERE o.circle_id = c.id AND o.user_id NOT IN (p_user_id) AND o.role = 'admin'
                    AND o.status = 'active'
              );
        END IF;
    END LOOP;
    -- Circles where the user is the last admin but not the creator: promote the earliest member.
    UPDATE social.circle_member AS m SET role = 'admin'
    FROM (
        SELECT DISTINCT ON (o.circle_id) o.circle_id, o.user_id
        FROM social.circle_member AS mine
        INNER JOIN social.circle_member AS o
            ON o.circle_id = mine.circle_id AND o.user_id <> p_user_id AND o.status = 'active'
        WHERE mine.user_id = p_user_id AND mine.role = 'admin' AND mine.status = 'active'
          AND NOT EXISTS (
              SELECT 1 FROM social.circle_member AS a2
              WHERE a2.circle_id = mine.circle_id AND a2.user_id <> p_user_id
                AND a2.role = 'admin' AND a2.status = 'active'
          )
        ORDER BY o.circle_id, o.joined_at, o.user_id
    ) AS pick
    WHERE m.circle_id = pick.circle_id AND m.user_id = pick.user_id;
    UPDATE social.care_circle AS cc SET member_count = greatest(cc.member_count - 1, 0)
    FROM social.circle_member AS m
    WHERE m.circle_id = cc.id AND m.user_id = p_user_id AND m.status = 'active';

    -- 3. The user's id inside other people's rows (no foreign key there).
    UPDATE nutrition.food_item SET created_by = NULL WHERE created_by = p_user_id;
    UPDATE nutrition.food_item SET updated_by = NULL WHERE updated_by = p_user_id;
    UPDATE nutrition.food_alias SET created_by = NULL WHERE created_by = p_user_id;
    UPDATE nutrition.food_alias SET updated_by = NULL WHERE updated_by = p_user_id;
    UPDATE nutrition.barcode_product SET created_by = NULL WHERE created_by = p_user_id;
    UPDATE nutrition.barcode_product SET updated_by = NULL WHERE updated_by = p_user_id;
    UPDATE social.care_circle SET created_by = NULL WHERE created_by = p_user_id;
    UPDATE social.care_circle SET updated_by = NULL WHERE updated_by = p_user_id;
    UPDATE auth.user_account SET created_by = NULL WHERE created_by = p_user_id AND id <> p_user_id;
    UPDATE auth.user_account SET updated_by = NULL WHERE updated_by = p_user_id AND id <> p_user_id;
    UPDATE notify.notification SET params = params - 'user_id'
    WHERE user_id <> p_user_id AND params ->> 'user_id' = v_text;

    -- 4. The account: every personal row cascades (doc 05: ON DELETE CASCADE to auth.user_account).
    DELETE FROM auth.user_account WHERE id = p_user_id;

    INSERT INTO privacy.deletion_log (user_hash, requested_at, rows_archived)
    VALUES (v_hash, v_requested, o_archived);

    -- 5. Last: the audit trail without personal values. Every row about the user (by actor, key or
    --    values) keeps what happened and when, but no id, key or values, including the rows this
    --    erasure just wrote through the audit triggers. Values are matched anywhere in the row image
    --    (S16: rows of other users that named this one, e.g. invited_by, referrer_id, sender_id,
    --    were missed when only user_id / created_by were checked).
    UPDATE audit.change_log SET
        old_values = NULL, new_values = NULL, actor_user_id = NULL,
        row_pk = CASE WHEN row_pk LIKE '%' || v_text || '%' THEN 'erased' ELSE row_pk END
    WHERE actor_user_id = p_user_id
       OR row_pk LIKE '%' || v_text || '%'
       OR old_values::text LIKE '%' || v_text || '%'
       OR new_values::text LIKE '%' || v_text || '%';
    UPDATE audit.security_event SET user_id = NULL, ip = NULL, details = '{}'::jsonb
    WHERE user_id = p_user_id;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_apply_row_retention()
RETURNS TABLE (item text, purged bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_days integer;
    v_n bigint;
BEGIN
    PERFORM set_config('lock_timeout', '5s', true);

    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'social.chat_message';
    DELETE FROM social.chat_message
    WHERE deleted_at IS NOT NULL AND deleted_at < now() - make_interval(days => coalesce(v_days, 30));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    item := 'social.chat_message'; purged := v_n; RETURN NEXT;

    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'ai.conversation';
    DELETE FROM ai.conversation
    WHERE last_message_at < now() - make_interval(days => coalesce(v_days, 365))
       OR (deleted_at IS NOT NULL AND deleted_at < now() - interval '30 days');
    GET DIAGNOSTICS v_n = ROW_COUNT;
    item := 'ai.conversation'; purged := v_n; RETURN NEXT;

    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'ai.usage_event';
    DELETE FROM ai.usage_event WHERE created_at < now() - make_interval(days => coalesce(v_days, 396));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    item := 'ai.usage_event'; purged := v_n; RETURN NEXT;

    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'privacy.consent_archive';
    DELETE FROM privacy.consent_archive WHERE archived_at < now() - make_interval(days => coalesce(v_days, 2922));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    item := 'privacy.consent_archive'; purged := v_n; RETURN NEXT;

    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'billing.transaction_archive';
    DELETE FROM billing.transaction_archive WHERE archived_at < now() - make_interval(days => coalesce(v_days, 2922));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    item := 'billing.transaction_archive'; purged := v_n; RETURN NEXT;

    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'privacy.deletion_log';
    DELETE FROM privacy.deletion_log WHERE completed_at < now() - make_interval(days => coalesce(v_days, 2922));
    GET DIAGNOSTICS v_n = ROW_COUNT;
    item := 'privacy.deletion_log'; purged := v_n; RETURN NEXT;
END
$$;

CREATE OR REPLACE FUNCTION ops.fn_expired_attachments(p_limit integer DEFAULT 500)
RETURNS TABLE (object_key text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_days integer;
BEGIN
    SELECT p.retention_days INTO v_days FROM privacy.retention_policy AS p WHERE p.table_name = 'support.attachment';
    RETURN QUERY
    WITH due AS (
        SELECT t.id, t.screenshot_key FROM support.ticket AS t
        WHERE t.screenshot_key IS NOT NULL AND t.created_at < now() - make_interval(days => coalesce(v_days, 180))
        ORDER BY t.created_at
        LIMIT least(greatest(coalesce(p_limit, 500), 1), 5000)
        FOR UPDATE SKIP LOCKED
    ),
    cleared AS (
        UPDATE support.ticket AS t SET screenshot_key = NULL FROM due WHERE t.id = due.id RETURNING due.screenshot_key
    )
    SELECT cleared.screenshot_key::text FROM cleared;
END
$$;

COMMENT ON FUNCTION ops.fn_claim_exports(integer) IS 'Worker: claim queued data exports (SKIP LOCKED)';
COMMENT ON FUNCTION ops.fn_export_user(uuid) IS
'Worker: all rows a user owns as JSON per table (catalog-driven; secrets excluded)';
COMMENT ON PROCEDURE ops.pr_finish_export(uuid, boolean, text, bigint, text) IS
'Worker: mark an export ready (7 days, notification) or retry / fail it';
COMMENT ON FUNCTION ops.fn_expire_exports(integer) IS 'Worker: expire exports after 7 days; returns the keys';
COMMENT ON FUNCTION ops.fn_due_deletions(integer) IS
'Worker: deletions whose 30-day grace is over, with the receipt address and the Apple token to revoke';
COMMENT ON FUNCTION ops.fn_user_files(uuid) IS 'Worker: storage keys of a user''s reports, screenshots, exports';
COMMENT ON PROCEDURE ops.pr_mark_deletion_receipt(uuid) IS 'Worker: the deletion receipt was sent';
COMMENT ON PROCEDURE ops.pr_delete_user(uuid, integer) IS
'Worker: erase an account (archives hashed, circles handed over, audit values removed)';
COMMENT ON FUNCTION ops.fn_apply_row_retention() IS
'Worker: purge rows past privacy.retention_policy; returns counts per item (metric)';
COMMENT ON FUNCTION ops.fn_expired_attachments(integer) IS
'Worker: support screenshots past retention: key cleared and returned for deletion';

REVOKE ALL ON FUNCTION ops.fn_claim_exports(integer) FROM public;
REVOKE ALL ON FUNCTION ops.fn_export_user(uuid) FROM public;
REVOKE ALL ON PROCEDURE ops.pr_finish_export(uuid, boolean, text, bigint, text) FROM public;
REVOKE ALL ON FUNCTION ops.fn_expire_exports(integer) FROM public;
REVOKE ALL ON FUNCTION ops.fn_due_deletions(integer) FROM public;
REVOKE ALL ON FUNCTION ops.fn_user_files(uuid) FROM public;
REVOKE ALL ON PROCEDURE ops.pr_mark_deletion_receipt(uuid) FROM public;
REVOKE ALL ON PROCEDURE ops.pr_delete_user(uuid, integer) FROM public;
REVOKE ALL ON FUNCTION ops.fn_apply_row_retention() FROM public;
REVOKE ALL ON FUNCTION ops.fn_expired_attachments(integer) FROM public;
GRANT EXECUTE ON FUNCTION ops.fn_claim_exports(integer) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_export_user(uuid) TO app_worker;
GRANT EXECUTE ON PROCEDURE ops.pr_finish_export(uuid, boolean, text, bigint, text) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_expire_exports(integer) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_due_deletions(integer) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_user_files(uuid) TO app_worker;
GRANT EXECUTE ON PROCEDURE ops.pr_mark_deletion_receipt(uuid) TO app_worker;
GRANT EXECUTE ON PROCEDURE ops.pr_delete_user(uuid, integer) TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_apply_row_retention() TO app_worker;
GRANT EXECUTE ON FUNCTION ops.fn_expired_attachments(integer) TO app_worker;
