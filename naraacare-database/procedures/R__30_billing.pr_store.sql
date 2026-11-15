-- Store subscriptions, transactions and notifications (doc 04 section 2.12, doc 07 SEC-6.1-6.3, S11).
-- The API calls these only with state it has verified with the store (Play Developer API / App Store
-- signed JWS); the app's own claims about a purchase are never stored.
--   * pr_upsert_subscription (POST /billing/purchases/verify): binds a purchase token or
--     original transaction id to the caller. A key that belongs to another account is refused with
--     o_status = 'token_in_use' and a security event (T11: receipt sharing), nothing changes.
--   * pr_apply_store_state (webhooks, reconcile): updates the subscription with that key, whoever owns
--     it; o_user_id is the owner or NULL when unknown.
--   * pr_record_transaction: billing history, idempotent on the store transaction id.
--   * pr_record_store_notification / pr_finish_store_notification: idempotency per notification id
--     (a replayed webhook returns 'duplicate' and is not processed again).
-- Created as api_definer, which owns every API function (doc 05 section 7); LOCAL = this script only.
SET LOCAL ROLE api_definer;

CREATE OR REPLACE PROCEDURE billing.pr_upsert_subscription(
    p_user_id uuid,
    p_platform common.code,
    p_product_id common.opaque_ref,
    p_purchase_token common.opaque_token,
    p_original_transaction_id common.opaque_ref,
    p_status common.code,
    p_auto_renew boolean,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_environment common.code,
    INOUT o_subscription_id uuid DEFAULT NULL,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_owner uuid;
BEGIN
    PERFORM common.fn_assert_actor(p_user_id);
    SELECT s.id, s.user_id INTO o_subscription_id, v_owner
    FROM billing.subscription AS s
    WHERE s.platform = p_platform AND s.deleted_at IS NULL AND (
        (p_purchase_token IS NOT NULL AND s.purchase_token = p_purchase_token)
        OR (p_original_transaction_id IS NOT NULL AND s.original_transaction_id = p_original_transaction_id)
    )
    FOR UPDATE;

    IF FOUND AND v_owner <> p_user_id THEN
        CALL audit.pr_log_security_event(
            'purchase_token_reuse', p_user_id, NULL, NULL, NULL,
            jsonb_build_object('platform', p_platform)
        );
        o_subscription_id := NULL;
        o_status := 'token_in_use';
        RETURN;
    END IF;

    IF FOUND THEN
        UPDATE billing.subscription AS s
        SET product_id = p_product_id, status = p_status, auto_renew = p_auto_renew,
            current_period_start = p_period_start, current_period_end = p_period_end,
            environment = p_environment, last_verified_at = now(),
            updated_by = p_user_id, updated_at = now()
        WHERE s.id = o_subscription_id;
        o_status := 'updated';
        RETURN;
    END IF;

    INSERT INTO billing.subscription (
        user_id, platform, product_id, purchase_token, original_transaction_id,
        status, auto_renew, current_period_start, current_period_end, environment, last_verified_at,
        created_by, updated_by
    )
    VALUES (
        p_user_id, p_platform, p_product_id, p_purchase_token,
        p_original_transaction_id, p_status, p_auto_renew, p_period_start, p_period_end, p_environment,
        now(), p_user_id, p_user_id
    )
    RETURNING id INTO o_subscription_id;
    o_status := 'created';
END
$$;

COMMENT ON PROCEDURE billing.pr_upsert_subscription (
    uuid, common.code, common.opaque_ref, common.opaque_token, common.opaque_ref,
    common.code, boolean, timestamptz, timestamptz, common.code, uuid, text
) IS 'Bind a verified store subscription to the caller; a key owned by another account is refused';
REVOKE ALL ON PROCEDURE billing.pr_upsert_subscription(
    uuid, common.code, common.opaque_ref, common.opaque_token, common.opaque_ref,
    common.code, boolean, timestamptz, timestamptz, common.code, uuid, text
) FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_upsert_subscription(
    uuid, common.code, common.opaque_ref, common.opaque_token, common.opaque_ref,
    common.code, boolean, timestamptz, timestamptz, common.code, uuid, text
) TO app_rw;

CREATE OR REPLACE PROCEDURE billing.pr_apply_store_state(
    p_platform common.code,
    p_purchase_token common.opaque_token,
    p_original_transaction_id common.opaque_ref,
    p_product_id common.opaque_ref,
    p_status common.code,
    p_auto_renew boolean,
    p_period_start timestamptz,
    p_period_end timestamptz,
    p_environment common.code,
    INOUT o_user_id uuid DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    UPDATE billing.subscription AS s
    SET product_id = coalesce(p_product_id, s.product_id), status = p_status,
        auto_renew = coalesce(p_auto_renew, s.auto_renew),
        current_period_start = coalesce(p_period_start, s.current_period_start),
        current_period_end = coalesce(p_period_end, s.current_period_end),
        environment = coalesce(p_environment, s.environment), last_verified_at = now(), updated_at = now()
    WHERE s.platform = p_platform AND s.deleted_at IS NULL AND (
        (p_purchase_token IS NOT NULL AND s.purchase_token = p_purchase_token)
        OR (p_original_transaction_id IS NOT NULL AND s.original_transaction_id = p_original_transaction_id)
    )
    RETURNING s.user_id INTO o_user_id;
END
$$;

COMMENT ON PROCEDURE billing.pr_apply_store_state (
    common.code, common.opaque_token, common.opaque_ref, common.opaque_ref, common.code, boolean,
    timestamptz, timestamptz, common.code, uuid
) IS 'Apply store-verified state (webhook, reconcile) to the subscription with that key; returns its owner';
REVOKE ALL ON PROCEDURE billing.pr_apply_store_state(
    common.code, common.opaque_token, common.opaque_ref, common.opaque_ref, common.code, boolean,
    timestamptz, timestamptz, common.code, uuid
) FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_apply_store_state(
    common.code, common.opaque_token, common.opaque_ref, common.opaque_ref, common.code, boolean,
    timestamptz, timestamptz, common.code, uuid
) TO app_rw, app_worker;

CREATE OR REPLACE PROCEDURE billing.pr_record_transaction(
    p_platform common.code,
    p_purchase_token common.opaque_token,
    p_original_transaction_id common.opaque_ref,
    p_store_transaction_id common.opaque_ref,
    p_type common.code,
    p_amount_micros bigint,
    p_currency common.currency,
    p_occurred_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
DECLARE
    v_subscription uuid;
BEGIN
    SELECT s.id INTO v_subscription
    FROM billing.subscription AS s
    WHERE s.platform = p_platform AND s.deleted_at IS NULL AND (
        (p_purchase_token IS NOT NULL AND s.purchase_token = p_purchase_token)
        OR (p_original_transaction_id IS NOT NULL AND s.original_transaction_id = p_original_transaction_id)
    );
    IF NOT FOUND THEN
        RETURN;
    END IF;
    INSERT INTO billing.store_transaction (
        subscription_id, store_transaction_id, type, amount_micros, currency, occurred_at
    )
    VALUES (v_subscription, p_store_transaction_id, p_type, p_amount_micros, p_currency, p_occurred_at)
    ON CONFLICT ON CONSTRAINT uq_store_transaction__store_id DO NOTHING;
END
$$;

COMMENT ON PROCEDURE billing.pr_record_transaction (
    common.code, common.opaque_token, common.opaque_ref, common.opaque_ref, common.code, bigint,
    common.currency, timestamptz
) IS 'Record a store transaction for billing history (idempotent on the store transaction id)';
REVOKE ALL ON PROCEDURE billing.pr_record_transaction(
    common.code, common.opaque_token, common.opaque_ref, common.opaque_ref, common.code, bigint,
    common.currency, timestamptz
) FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_record_transaction(
    common.code, common.opaque_token, common.opaque_ref, common.opaque_ref, common.code, bigint,
    common.currency, timestamptz
) TO app_rw, app_worker;

CREATE OR REPLACE PROCEDURE billing.pr_record_store_notification(
    p_platform common.code,
    p_notification_uid common.opaque_ref,
    p_type common.code,
    p_payload_sha256 common.sha256_hex,
    INOUT o_status text DEFAULT NULL
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    INSERT INTO billing.store_notification (platform, notification_uid, type, payload_sha256)
    VALUES (p_platform, p_notification_uid, p_type, p_payload_sha256)
    ON CONFLICT ON CONSTRAINT uq_store_notification__platform_uid DO NOTHING;
    IF FOUND THEN
        o_status := 'new';
        RETURN;
    END IF;
    -- Seen before: process again only if the earlier attempt failed.
    SELECT CASE WHEN n.status = 'failed' THEN 'retry' ELSE 'duplicate' END INTO o_status
    FROM billing.store_notification AS n
    WHERE n.platform = p_platform AND n.notification_uid = p_notification_uid;
END
$$;

COMMENT ON PROCEDURE billing.pr_record_store_notification (common.code, common.opaque_ref, common.code, common.sha256_hex, text) IS
'Record a store notification once: new, duplicate (already handled) or retry (failed before)';
REVOKE ALL ON PROCEDURE billing.pr_record_store_notification(common.code, common.opaque_ref, common.code, common.sha256_hex, text)
FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_record_store_notification(common.code, common.opaque_ref, common.code, common.sha256_hex, text)
TO app_rw;

CREATE OR REPLACE PROCEDURE billing.pr_finish_store_notification(
    p_platform common.code, p_notification_uid common.opaque_ref, p_status common.code
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF p_status NOT IN ('processed', 'ignored', 'failed') THEN
        RAISE EXCEPTION 'unknown notification status' USING ERRCODE = '22023', DETAIL = 'STATUS_INVALID';
    END IF;
    UPDATE billing.store_notification AS n
    SET status = p_status, processed_at = now()
    WHERE n.platform = p_platform AND n.notification_uid = p_notification_uid;
END
$$;

COMMENT ON PROCEDURE billing.pr_finish_store_notification (common.code, common.opaque_ref, common.code) IS
'Mark a store notification processed, ignored or failed';
REVOKE ALL ON PROCEDURE billing.pr_finish_store_notification(common.code, common.opaque_ref, common.code) FROM public;
GRANT EXECUTE ON PROCEDURE billing.pr_finish_store_notification(common.code, common.opaque_ref, common.code) TO app_rw;
