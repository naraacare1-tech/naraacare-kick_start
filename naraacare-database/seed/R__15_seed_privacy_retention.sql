-- Retention for non-partitioned tables (doc 05 section 9; pending legal approval OQ-48).
-- Partitioned tables use ops.partition_config.retention_months instead.
-- Read by ops.pr_purge_auth_artifacts (Session 03) and, from Session 15, ops.fn_apply_row_retention
-- (chat, Rin, usage, archives) and ops.fn_expired_attachments (support screenshots). Report and export
-- files expire after 7 days in their own jobs.

INSERT INTO privacy.retention_policy (table_name, retention_days, action) VALUES
('auth.otp_challenge', 7, 'purge'),
('auth.login_attempt', 90, 'purge'),
('auth.refresh_token', 30, 'purge'),
('social.chat_message', 30, 'purge'),
('ai.conversation', 365, 'purge'),
('ai.usage_event', 396, 'purge'),
('support.attachment', 180, 'purge'),
('privacy.consent_archive', 2922, 'purge'),
('billing.transaction_archive', 2922, 'purge'),
('privacy.deletion_log', 2922, 'purge')
ON CONFLICT (table_name) DO UPDATE SET
    retention_days = excluded.retention_days, action = excluded.action, updated_at = now();
