-- Session 16: privileges audit (doc 05 section 7, doc 07 SEC-4.4). A snapshot of who may do what,
-- compared with the reviewed expectation. Any change to roles, grants or RLS coverage fails here until
-- the snapshot below is updated on purpose (and reviewed): a grant can never slip in unnoticed.
-- Regenerate a function list with:
--   SELECT p.oid::regprocedure FROM pg_proc p WHERE has_function_privilege('<role>', p.oid, 'EXECUTE')
--   (application schemas only), then review the diff before committing it.
BEGIN;
SELECT no_plan();

-- 1. Role attributes: nobody but the bootstrap superuser is superuser or bypasses RLS; only the
--    migration owner may create roles; NOLOGIN for the owner of the API functions.
SELECT results_eq(
    $$SELECT rolname::text COLLATE "C", rolsuper, rolcreaterole, rolcreatedb, rolbypassrls, rolcanlogin
      FROM pg_roles
      WHERE rolname IN ('migration_owner', 'api_definer', 'app_rw', 'app_worker', 'app_readonly', 'reporting')
      ORDER BY rolname$$,
    $$VALUES
      ('api_definer' COLLATE "C", false, false, false, false, false),
      ('app_readonly', false, false, false, false, true),
      ('app_rw', false, false, false, false, true),
      ('app_worker', false, false, false, false, true),
      ('migration_owner', false, true, false, false, true),
      ('reporting', false, false, false, false, true)$$,
    'role attributes match the design'
);
SELECT is(
    (SELECT array_agg(rolname::text ORDER BY 1) FROM pg_roles
     WHERE (rolsuper OR rolbypassrls) AND rolname <> 'postgres' AND rolname !~ '^pg_'),
    NULL,
    'no application role is superuser or BYPASSRLS'
);

-- 2. The runtime roles are not members of anything (no inherited rights).
SELECT is(
    (SELECT array_agg(r.rolname || ' in ' || g.rolname ORDER BY 1)
     FROM pg_auth_members AS m
     INNER JOIN pg_roles AS r ON r.oid = m.member
     INNER JOIN pg_roles AS g ON g.oid = m.roleid
     WHERE r.rolname IN ('app_rw', 'app_worker', 'app_readonly', 'reporting', 'api_definer')),
    NULL,
    'runtime roles belong to no other role'
);

-- 3. No direct table or sequence access for the runtime roles: everything goes through functions.
--    reporting may only SELECT the aggregated report views.
SELECT is(
    (SELECT array_agg(DISTINCT grantee || ' ' || privilege_type || ' ' || table_schema || '.' || table_name)
     FROM information_schema.role_table_grants
     WHERE grantee IN ('app_rw', 'app_worker', 'app_readonly')),
    NULL,
    'app_rw / app_worker / app_readonly have no table privileges'
);
SELECT is(
    (SELECT array_agg(DISTINCT g.privilege_type || ' ' || g.table_schema || '.' || g.table_name)
     FROM information_schema.role_table_grants AS g
     INNER JOIN pg_class AS c ON c.relname = g.table_name
     INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace AND n.nspname = g.table_schema
     WHERE g.grantee = 'reporting' AND NOT (g.privilege_type = 'SELECT' AND c.relkind = 'v'
           AND g.table_schema = 'report' AND g.table_name LIKE 'v\_%')),
    NULL,
    'reporting can only SELECT report.v_* views'
);
SELECT is(
    (SELECT array_agg(DISTINCT grantee || ' ' || sequence_schema || '.' || sequence_name)
     FROM information_schema.usage_privileges AS u
     INNER JOIN information_schema.sequences AS s
       ON s.sequence_schema = u.object_schema AND s.sequence_name = u.object_name
     WHERE u.grantee IN ('app_rw', 'app_worker', 'app_readonly', 'reporting')),
    NULL,
    'runtime roles have no sequence privileges'
);

-- 4. PUBLIC gets nothing: no function EXECUTE, no CREATE in any schema.
SELECT is(
    (SELECT array_agg(p.oid::regprocedure::text ORDER BY 1)
     FROM pg_proc AS p
     INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')
       AND has_function_privilege('public', p.oid, 'EXECUTE')),
    NULL,
    'PUBLIC can execute no application function'
);
SELECT is(
    (SELECT array_agg(nspname::text ORDER BY 1) FROM pg_namespace
     WHERE nspname !~ '^pg_' AND nspname <> 'information_schema'
       AND has_schema_privilege('public', oid, 'CREATE')),
    NULL,
    'PUBLIC can create objects in no schema'
);

-- 5. SECURITY DEFINER routines: owned by api_definer (API) or migration_owner (ops allow-list), and
--    every one pins search_path.
SELECT is(
    (SELECT array_agg(p.oid::regprocedure::text ORDER BY 1)
     FROM pg_proc AS p
     INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
     WHERE p.prosecdef AND n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')
       AND (pg_get_userbyid(p.proowner) NOT IN ('api_definer', 'migration_owner')
            OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) AS c WHERE c LIKE 'search_path=%'))),
    NULL,
    'every SECURITY DEFINER routine has an expected owner and a fixed search_path'
);

-- 6. RLS: every table with a user_id column has RLS on, except the reviewed list below.
--    auth.*: sign-in, sign-up and reset run before any user is known (functions check every case);
--    billing.*: store webhooks and reconciliation act across users; audit.security_event: insert-only
--    for the API; privacy.consent_record: append-only (no UPDATE/DELETE grant, trigger).
SELECT is(
    (SELECT array_agg((n.nspname || '.' || c.relname)::text ORDER BY (n.nspname || '.' || c.relname) COLLATE "C")
     FROM pg_class AS c
     INNER JOIN pg_namespace AS n ON n.oid = c.relnamespace
     INNER JOIN pg_attribute AS a ON a.attrelid = c.oid AND a.attname = 'user_id' AND NOT a.attisdropped
     WHERE c.relkind IN ('r', 'p') AND NOT c.relispartition AND NOT c.relrowsecurity
       AND n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')),
    ARRAY[
        'audit.security_event', 'auth.identity_link', 'auth.otp_challenge', 'auth.password_history',
        'auth.refresh_token', 'billing.entitlement_grant', 'billing.referral_code',
        'billing.subscription', 'privacy.consent_record'
    ]::text[],
    'tables with user_id and no RLS are exactly the reviewed exceptions'
);

-- 7. Function grants per runtime role (the reviewed snapshot).
SELECT is(
    (
        SELECT array_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text COLLATE "C")
        FROM pg_proc AS p
        INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')
          AND has_function_privilege('app_rw', p.oid, 'EXECUTE')
    ),
    ARRAY[
        'activity.fn_workouts(uuid,date,uuid)',
        'activity.pr_delete_workout(uuid,uuid,integer)',
        'activity.pr_log_workout(uuid,uuid,timestamp with time zone,common.code,integer,text,date)',
        'ai.fn_conversations(uuid,text,timestamp with time zone,integer)',
        'ai.fn_history(uuid,uuid,integer)',
        'ai.fn_messages(uuid,uuid,timestamp with time zone,integer)',
        'ai.fn_pending_action(uuid,uuid)',
        'ai.fn_rin_context(uuid)',
        'ai.fn_usage_month(uuid)',
        'ai.pr_append_message(uuid,uuid,text,common.safe_text,uuid,uuid,uuid,text)',
        'ai.pr_create_conversation(uuid,common.safe_text,uuid)',
        'ai.pr_create_pending_action(uuid,uuid,text,jsonb,uuid,timestamp with time zone)',
        'ai.pr_delete_conversation(uuid,uuid)',
        'ai.pr_delete_memory(uuid)',
        'ai.pr_record_usage(uuid,text,text,integer,integer,integer,integer,bigint)',
        'ai.pr_resolve_pending_action(uuid,uuid,text,uuid)',
        'ai.pr_upsert_memory(uuid,common.safe_text)',
        'app.fn_changes_since(uuid,timestamp with time zone,uuid,integer)',
        'app.fn_get_profile(uuid)',
        'app.fn_latest_target_snapshot(uuid,date)',
        'app.fn_streak(uuid,date)',
        'app.fn_username_available(common.username)',
        'app.pr_complete_onboarding(uuid,jsonb,jsonb,common.app_version,inet,date)',
        'app.pr_save_onboarding_step(uuid,smallint,common.code,common.code,common.safe_text,numeric,numeric,common.code,numeric,common.code[],smallint,common.code,common.code,smallint)',
        'app.pr_set_sleep_goal(uuid,integer)',
        'app.pr_set_username(uuid,common.username)',
        'app.pr_update_profile(uuid,common.safe_text,common.code,common.code,smallint,numeric,numeric,numeric,common.code,common.code,common.code,common.code[],jsonb,date)',
        'app.pr_update_settings(uuid,common.code,common.code,common.code,common.iana_timezone,common.locale,time without time zone,time without time zone,boolean)',
        'audit.pr_log_security_event(common.code,uuid,inet,uuid,common.code,jsonb)',
        'auth.fn_find_account_by_email(common.email)',
        'auth.fn_find_identity(common.code,common.opaque_ref)',
        'auth.fn_get_otp_challenge(uuid)',
        'auth.fn_login_failures_recent(common.email,interval)',
        'auth.fn_otp_challenge_email(uuid)',
        'auth.fn_password_history(uuid)',
        'auth.fn_refresh_token_lookup(common.blind_index)',
        'auth.fn_unknown_email_locked_until(common.email)',
        'auth.pr_create_account(common.email,common.argon2_hash,uuid,common.otp_code,uuid,uuid,text,integer)',
        'auth.pr_create_oauth_account(common.code,common.opaque_ref,common.email,uuid,uuid,text)',
        'auth.pr_create_otp_challenge(common.email,common.code,common.otp_code,uuid,text,integer)',
        'auth.pr_issue_refresh_token(uuid,common.blind_index,uuid,uuid,uuid,timestamp with time zone)',
        'auth.pr_link_identity(uuid,common.code,common.opaque_ref,common.email)',
        'auth.pr_record_login_attempt(common.email,inet,boolean,text,timestamp with time zone)',
        'auth.pr_rehash_password(uuid,common.argon2_hash,common.argon2_hash,boolean)',
        'auth.pr_resend_otp(uuid,common.otp_code,text,integer)',
        'auth.pr_revoke_tokens(uuid,common.code,common.code,uuid,uuid,integer)',
        'auth.pr_rotate_refresh_token(common.blind_index,common.blind_index,uuid,uuid,uuid,uuid,timestamp with time zone,text,text)',
        'auth.pr_set_password(uuid,common.argon2_hash,uuid)',
        'auth.pr_store_provider_token(uuid,common.code,common.opaque_ref,common.opaque_token,boolean)',
        'auth.pr_verify_otp(uuid,boolean,uuid,text,integer,text)',
        'billing.fn_billing_history(uuid,timestamp with time zone,integer)',
        'billing.fn_current_entitlement(uuid)',
        'billing.fn_plans()',
        'billing.fn_referral_progress(uuid)',
        'billing.fn_subscription(uuid)',
        'billing.pr_apply_store_state(common.code,common.opaque_token,common.opaque_ref,common.opaque_ref,common.code,boolean,timestamp with time zone,timestamp with time zone,common.code,uuid)',
        'billing.pr_attribute_referral(uuid,common.referral_code,uuid,text)',
        'billing.pr_ensure_referral_code(uuid,text)',
        'billing.pr_finish_store_notification(common.code,common.opaque_ref,common.code)',
        'billing.pr_record_store_notification(common.code,common.opaque_ref,common.code,common.sha256_hex,text)',
        'billing.pr_record_transaction(common.code,common.opaque_token,common.opaque_ref,common.opaque_ref,common.code,bigint,common.currency,timestamp with time zone)',
        'billing.pr_upsert_subscription(uuid,common.code,common.opaque_ref,common.opaque_token,common.opaque_ref,common.code,boolean,timestamp with time zone,timestamp with time zone,common.code,uuid,text)',
        'hydration.fn_day_inputs(uuid,date)',
        'hydration.fn_drinks_for_user(uuid)',
        'hydration.fn_intakes(uuid,date,uuid)',
        'hydration.pr_delete_intake(uuid,uuid,integer)',
        'hydration.pr_log_intake(uuid,uuid,timestamp with time zone,common.code,uuid,integer,common.code,text,date)',
        'hydration.pr_save_custom_drink(uuid,text,numeric,common.code,uuid)',
        'hydration.pr_set_temperature(uuid,numeric,date)',
        'hydration.pr_update_intake(uuid,uuid,integer,integer,common.code,uuid,integer)',
        'hydration.pr_upsert_daily_summary(uuid,date,integer,numeric,boolean,common.version_label,boolean)',
        'notify.fn_notification_preferences(uuid)',
        'notify.fn_notifications(uuid,uuid,timestamp with time zone,integer)',
        'notify.fn_reminders(uuid)',
        'notify.pr_mark_notifications_read(uuid,uuid,uuid[])',
        'notify.pr_register_device(uuid,uuid,common.code,common.opaque_token,common.app_version,uuid)',
        'notify.pr_revoke_device(uuid,uuid,boolean)',
        'notify.pr_set_notification_preferences(uuid,jsonb)',
        'notify.pr_set_reminders(uuid,jsonb)',
        'nutrition.fn_alias_match(text[])',
        'nutrition.fn_barcode_lookup(common.barcode)',
        'nutrition.fn_daily_summary(uuid,date)',
        'nutrition.fn_food_detail(uuid)',
        'nutrition.fn_food_portions(uuid[])',
        'nutrition.fn_meal_breakdown(uuid,uuid)',
        'nutrition.fn_meals_by_date(uuid,date)',
        'nutrition.fn_preview_meal(uuid,jsonb)',
        'nutrition.fn_recent_foods(uuid,integer)',
        'nutrition.fn_recent_meals(uuid,integer)',
        'nutrition.fn_saved_meals(uuid)',
        'nutrition.fn_search_foods(text,integer)',
        'nutrition.pr_admin_upsert_food(uuid,uuid,text,common.code,common.code,numeric,boolean,text,jsonb,jsonb,common.code,uuid)',
        'nutrition.pr_delete_meal(uuid,uuid,integer)',
        'nutrition.pr_delete_saved_meal(uuid,uuid)',
        'nutrition.pr_log_meal(uuid,uuid,timestamp with time zone,common.code,common.code,jsonb,text,date)',
        'nutrition.pr_save_meal_template(uuid,text,jsonb,uuid)',
        'nutrition.pr_update_meal(uuid,uuid,integer,common.code,jsonb,integer)',
        'nutrition.pr_upsert_barcode_product(uuid,common.barcode,text,text,numeric,jsonb,uuid)',
        'ops.fn_ping()',
        'privacy.fn_current_consents(uuid)',
        'privacy.fn_exports(uuid,uuid)',
        'privacy.fn_privacy_status(uuid)',
        'privacy.pr_cancel_deletion(uuid,boolean)',
        'privacy.pr_record_consent(uuid,common.code,common.version_label,boolean,common.app_version,inet,bigint)',
        'privacy.pr_request_deletion(uuid,timestamp with time zone,boolean)',
        'privacy.pr_request_export(uuid,uuid,uuid,text,boolean)',
        'ref.fn_bootstrap()',
        'ref.fn_calc_context()',
        'ref.fn_policies()',
        'report.fn_report_jobs(uuid,uuid,timestamp with time zone,integer)',
        'report.pr_create_report_job(uuid,uuid,text,date,date,text[],uuid,text,boolean)',
        'sleep.fn_summary(uuid,date,uuid)',
        'sleep.pr_delete_entry(uuid,uuid,integer)',
        'sleep.pr_log_entry(uuid,uuid,timestamp with time zone,timestamp with time zone,jsonb,text,date)',
        'sleep.pr_update_entry(uuid,uuid,integer,timestamp with time zone,timestamp with time zone,jsonb,integer)',
        'social.fn_blocks(uuid)',
        'social.fn_circle_detail(uuid,uuid)',
        'social.fn_circle_feed(uuid,uuid,timestamp with time zone,integer)',
        'social.fn_circle_members(uuid,uuid,text,common.username,integer)',
        'social.fn_circles_for_user(uuid)',
        'social.fn_connections(uuid)',
        'social.fn_member_avatars(uuid,uuid,uuid)',
        'social.fn_messages(uuid,uuid,timestamp with time zone,integer)',
        'social.fn_pending_invites(uuid)',
        'social.fn_people_search(uuid,text)',
        'social.fn_suggestions(uuid)',
        'social.pr_block(uuid,uuid)',
        'social.pr_create_circle(uuid,common.safe_text,uuid[],text[],uuid,integer)',
        'social.pr_create_invite_link(uuid,uuid,common.blind_index,smallint,uuid,timestamp with time zone)',
        'social.pr_delete_circle(uuid,uuid)',
        'social.pr_delete_message(uuid,uuid,uuid)',
        'social.pr_invite_members(uuid,uuid,uuid[],integer)',
        'social.pr_leave_circle(uuid,uuid)',
        'social.pr_mark_read(uuid,uuid)',
        'social.pr_post_message(uuid,uuid,uuid,common.safe_text,uuid[],uuid,timestamp with time zone,text)',
        'social.pr_remove_connection(uuid,uuid)',
        'social.pr_remove_member(uuid,uuid,uuid)',
        'social.pr_request_connection(uuid,common.username,uuid,text)',
        'social.pr_resolve_invite_link(uuid,common.blind_index,uuid,text)',
        'social.pr_respond_connection(uuid,uuid,boolean)',
        'social.pr_respond_invite(uuid,uuid,text,text[],text)',
        'social.pr_revoke_invite_link(uuid,uuid,uuid)',
        'social.pr_set_circle_prefs(uuid,uuid,boolean,boolean,boolean,boolean,boolean,boolean)',
        'social.pr_set_member_role(uuid,uuid,uuid,text)',
        'social.pr_unblock(uuid,uuid)',
        'social.pr_update_circle(uuid,uuid,common.safe_text,common.code)',
        'social.pr_update_shares(uuid,uuid,text[])',
        'support.pr_create_feature_request(uuid,common.safe_text,common.safe_text,uuid)',
        'support.pr_create_ticket(uuid,text,common.safe_text,common.object_key,uuid,text)'
    ]::text[],
    'app_rw executes exactly the reviewed API routines'
);
SELECT is(
    (
        SELECT array_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text COLLATE "C")
        FROM pg_proc AS p
        INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')
          AND has_function_privilege('app_worker', p.oid, 'EXECUTE')
    ),
    ARRAY[
        'app.fn_get_profile(uuid)',
        'app.fn_latest_target_snapshot(uuid,date)',
        'audit.pr_log_security_event(common.code,uuid,inet,uuid,common.code,jsonb)',
        'auth.pr_revoke_tokens(uuid,common.code,common.code,uuid,uuid,integer)',
        'billing.fn_current_entitlement(uuid)',
        'billing.pr_apply_store_state(common.code,common.opaque_token,common.opaque_ref,common.opaque_ref,common.code,boolean,timestamp with time zone,timestamp with time zone,common.code,uuid)',
        'billing.pr_record_transaction(common.code,common.opaque_token,common.opaque_ref,common.opaque_ref,common.code,bigint,common.currency,timestamp with time zone)',
        'ops.fn_apply_row_retention()',
        'ops.fn_claim_exports(integer)',
        'ops.fn_claim_report_jobs(integer)',
        'ops.fn_day_ending_soon(timestamp with time zone,numeric,integer,time without time zone,time without time zone)',
        'ops.fn_due_deletions(integer)',
        'ops.fn_due_reminders(timestamp with time zone,time without time zone,time without time zone)',
        'ops.fn_expire_exports(integer)',
        'ops.fn_expire_reports(integer)',
        'ops.fn_expired_attachments(integer)',
        'ops.fn_export_user(uuid)',
        'ops.fn_is_quiet(time without time zone,time without time zone,time without time zone)',
        'ops.fn_ping()',
        'ops.fn_report_days(uuid)',
        'ops.fn_social_pushes(timestamp with time zone,timestamp with time zone,integer,time without time zone,time without time zone)',
        'ops.fn_subscriptions_to_reconcile(timestamp with time zone,integer)',
        'ops.fn_support_unforwarded(integer)',
        'ops.fn_user_files(uuid)',
        'ops.pr_apply_retention(date,integer)',
        'ops.pr_delete_user(uuid,integer)',
        'ops.pr_ensure_partitions(date,integer,integer)',
        'ops.pr_finish_export(uuid,boolean,text,bigint,text)',
        'ops.pr_finish_report_job(uuid,boolean,text,integer,text)',
        'ops.pr_mark_deletion_receipt(uuid)',
        'ops.pr_mark_support_forwarded(text,uuid,boolean)',
        'ops.pr_purge_auth_artifacts(timestamp with time zone,integer,integer)',
        'ops.pr_record_insight_usage(uuid,text,integer,integer,integer,integer,bigint)',
        'ops.pr_revoke_push_token(uuid)',
        'ops.pr_tally_referrals(timestamp with time zone,integer,integer)',
        'ref.fn_bootstrap()',
        'ref.fn_calc_context()',
        'ref.fn_policies()'
    ]::text[],
    'app_worker executes exactly the reviewed worker routines'
);
SELECT is(
    (
        SELECT array_agg(p.oid::regprocedure::text ORDER BY p.oid::regprocedure::text COLLATE "C")
        FROM pg_proc AS p
        INNER JOIN pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema', 'public')
          AND has_function_privilege('app_readonly', p.oid, 'EXECUTE')
    ),
    ARRAY[
        'app.fn_get_profile(uuid)',
        'app.fn_latest_target_snapshot(uuid,date)',
        'app.fn_username_available(common.username)',
        'billing.fn_current_entitlement(uuid)',
        'nutrition.fn_barcode_lookup(common.barcode)',
        'nutrition.fn_daily_summary(uuid,date)',
        'nutrition.fn_food_detail(uuid)',
        'nutrition.fn_food_portions(uuid[])',
        'nutrition.fn_meal_breakdown(uuid,uuid)',
        'nutrition.fn_meals_by_date(uuid,date)',
        'nutrition.fn_recent_foods(uuid,integer)',
        'nutrition.fn_recent_meals(uuid,integer)',
        'nutrition.fn_saved_meals(uuid)',
        'nutrition.fn_search_foods(text,integer)',
        'ops.fn_ping()',
        'privacy.fn_current_consents(uuid)',
        'ref.fn_bootstrap()',
        'ref.fn_calc_context()',
        'ref.fn_policies()'
    ]::text[],
    'app_readonly executes exactly the reviewed read-only routines'
);

SELECT * FROM finish();
ROLLBACK;
