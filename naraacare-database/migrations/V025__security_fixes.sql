-- V025 (Session 16, hand-written): fixes found by the Session 16 security tests.
-- (1) billing.pr_upsert_subscription logs 'purchase_token_reuse' when a second account presents a
-- store purchase that already belongs to another (doc 07 T11), but the event type was missing from
-- the CHECK, so the insert failed: the caller got 422 instead of 409 PURCHASE_TOKEN_IN_USE and no
-- event was recorded (tests/security/test_receipt_reuse.py in the backend). On a partitioned table
-- the constraint is replaced on every partition.
ALTER TABLE audit.security_event DROP CONSTRAINT security_event_event_type_check;
ALTER TABLE audit.security_event ADD CONSTRAINT security_event_event_type_check CHECK (event_type IN (
    'login_failed', 'lockout', 'refresh_reuse', 'validation_rejected', 'authz_denied',
    'rate_limited', 'webhook_rejected', 'admin_access', 'ops_alert', 'purchase_token_reuse'
));

-- ai.usage_event.model was the only table column of bare text (found by tests/950): the value comes
-- from server configuration and already had a format CHECK, but every text column goes through a
-- validating domain (doc 05 section 4).
ALTER TABLE ai.usage_event ALTER COLUMN model TYPE common.opaque_ref;

-- common.email accepted entity- and full-width-encoded markup such as
-- '&lt;style&gt;@import''javascript:alert(1)'';&lt;/style&gt;' (tests/950): it only excluded spaces,
-- @ and angle brackets. Now the same shape the API accepts: ASCII atoms @ a hostname. Re-adding the
-- constraint validates every stored address.
ALTER DOMAIN common.email DROP CONSTRAINT email_format;
ALTER DOMAIN common.email ADD CONSTRAINT email_format CHECK (
    char_length(value) BETWEEN 3 AND 254
    AND value = lower(value)
    AND value ~ '^[a-z0-9!#$%&''*+/=?^_`{|}~-]+(\.[a-z0-9!#$%&''*+/=?^_`{|}~-]+)*@[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$'
);
