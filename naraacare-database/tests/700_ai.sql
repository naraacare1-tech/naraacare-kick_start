-- Rin AI (Session 13; doc 04 section 2.10, doc 06 section 8, OQ-37): the gate (onboarding, STAR,
-- ai_processing consent, latest decision wins), idempotent prompts, token metering per local day
-- (input + output + cache write; cache reads free), the pending-action lifecycle (accept/dismiss once,
-- 24-hour expiry), the model context (no names, email or other users), soft delete and IDOR.
BEGIN;
SELECT no_plan();

CREATE FUNCTION pg_temp.u(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(28672 + n), 12, '0'))::uuid
$$;
INSERT INTO auth.user_account (id, email, status)
SELECT pg_temp.u(n), 'rin' || n || '@example.test', 'active' FROM generate_series(1, 4) AS n;
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at, full_name, username)
SELECT pg_temp.u(n), 6, CASE WHEN n = 4 THEN NULL ELSE now() END, 'Secret Name' || n, 'rin.user' || n
FROM generate_series(1, 4) AS n;
-- 1: STAR + consent; 2: STAR, consent withdrawn; 3: STANDARD + consent; 4: onboarding not done.
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
SELECT pg_temp.u(n), 'star', 'promo', now() - interval '1 day', now() + interval '30 days' FROM unnest(ARRAY[1, 2, 4]) AS n;
INSERT INTO privacy.consent_record (user_id, purpose, policy_version, granted, recorded_at) VALUES
(pg_temp.u(1), 'ai_processing', '1.0', TRUE, now() - interval '1 hour'),
(pg_temp.u(2), 'ai_processing', '1.0', TRUE, now() - interval '1 hour'),
(pg_temp.u(2), 'ai_processing', '1.0', FALSE, now() - interval '1 minute'),
(pg_temp.u(3), 'ai_processing', '1.0', TRUE, now() - interval '1 hour');

CREATE FUNCTION pg_temp.act(p_user uuid) RETURNS void LANGUAGE sql AS $$ SELECT set_config('app.user_id', p_user::text, TRUE) $$;
CREATE FUNCTION pg_temp.new_chat(p_user uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE c uuid;
BEGIN PERFORM pg_temp.act(p_user); CALL ai.pr_create_conversation(p_user, 'How much water today?', c); RETURN c; END $$;
CREATE FUNCTION pg_temp.say(p_user uuid, p_chat uuid, p_client uuid, p_text text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE m uuid; s text;
BEGIN PERFORM pg_temp.act(p_user); CALL ai.pr_append_message(p_user, p_chat, 'user', p_text, p_client, NULL, m, s); RETURN s; END $$;
CREATE FUNCTION pg_temp.propose(p_user uuid, p_chat uuid) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE a uuid; e timestamptz;
BEGIN
    PERFORM pg_temp.act(p_user);
    CALL ai.pr_create_pending_action(p_user, p_chat, 'drink', '{"drink_code": "water", "volume_ml": 250}', a, e);
    RETURN a;
END $$;
CREATE FUNCTION pg_temp.resolve(p_user uuid, p_action uuid, p_status text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.act(p_user); CALL ai.pr_resolve_pending_action(p_user, p_action, p_status, NULL); END $$;
CREATE FUNCTION pg_temp.usage(p_user uuid, i integer, o integer, c bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.act(p_user); CALL ai.pr_record_usage(p_user, 'chat', 'gpt-test', i, o, 0, 0, c); END $$;

-- ===== Gate =====
SELECT throws_like($$SELECT pg_temp.new_chat(pg_temp.u(3))$$, '%STAR%', 'STANDARD cannot use Rin (UPGRADE_REQUIRED)');
SELECT throws_like($$SELECT pg_temp.new_chat(pg_temp.u(2))$$, '%consent%', 'a withdrawn AI consent closes Rin (the latest decision wins)');
SELECT throws_like($$SELECT pg_temp.new_chat(pg_temp.u(4))$$, '%onboarding%', 'onboarding must be complete');
CREATE TEMP TABLE chat AS SELECT pg_temp.new_chat(pg_temp.u(1)) AS id;
SELECT isnt((SELECT id FROM chat), NULL, 'STAR + consent opens a chat');

-- ===== Messages =====
SELECT is(pg_temp.say(pg_temp.u(1), (SELECT id FROM chat), '0192f000-0000-7000-8000-0000000070c1', 'Hi Rin'), 'created', 'a prompt is stored');
SELECT is(pg_temp.say(pg_temp.u(1), (SELECT id FROM chat), '0192f000-0000-7000-8000-0000000070c1', 'Hi Rin'), 'duplicate',
    'the same client message id is stored once (retry after a lost connection)');
SELECT throws_ok(
    format($$SELECT pg_temp.say(%L, %L, uuidv7(), '<script>x</script>')$$, pg_temp.u(1), (SELECT id FROM chat)),
    '23514', NULL, 'markup is refused even for replies the API failed to clean'
);

-- ===== Metering =====
SELECT pg_temp.usage(pg_temp.u(1), 1000, 200, 650000);
SELECT pg_temp.usage(pg_temp.u(1), 10, 20, 350000);
SELECT is((SELECT used_micro_inr FROM ai.fn_usage_month(pg_temp.u(1))), 1000000::bigint,
    'the month''s spend is the sum of the calls'' costs (micro-rupees)');
SELECT is(
    (SELECT resets_at FROM ai.fn_usage_month(pg_temp.u(1))),
    (date_trunc('month', common.fn_local_date('Asia/Kolkata'))::date + interval '1 month')::timestamp
        AT TIME ZONE 'Asia/Kolkata',
    'the cap resets at the start of the next local month'
);
UPDATE ai.usage_event SET local_date = date_trunc('month', local_date)::date - 1 WHERE user_id = pg_temp.u(1);
SELECT is((SELECT used_micro_inr FROM ai.fn_usage_month(pg_temp.u(1))), 0::bigint, 'last month''s spend does not count');
SELECT throws_ok(
    format($$INSERT INTO ai.usage_event (user_id, local_date, feature, model, input_tokens, output_tokens, cost_micro_inr)
      VALUES (%L, current_date, 'chat', 'gpt-test', 1, 1, -1)$$, pg_temp.u(1)),
    '23514', NULL, 'a negative cost is refused'
);

-- ===== Pending actions =====
CREATE TEMP TABLE act1 AS SELECT pg_temp.propose(pg_temp.u(1), (SELECT id FROM chat)) AS id;
SELECT is((SELECT status FROM ai.pending_action WHERE id = (SELECT id FROM act1)), 'pending', 'a proposal is only pending');
SELECT lives_ok(format($$SELECT pg_temp.resolve(%L, %L, 'accepted')$$, pg_temp.u(1), (SELECT id FROM act1)), 'the user accepts');
SELECT throws_like(format($$SELECT pg_temp.resolve(%L, %L, 'accepted')$$, pg_temp.u(1), (SELECT id FROM act1)),
    '%', 'accepting twice is refused (ACTION_RESOLVED)');
CREATE TEMP TABLE act2 AS SELECT pg_temp.propose(pg_temp.u(1), (SELECT id FROM chat)) AS id;
UPDATE ai.pending_action SET created_at = now() - interval '25 hours', expires_at = now() - interval '1 hour'
WHERE id = (SELECT id FROM act2);
SELECT throws_ok(format($$SELECT pg_temp.resolve(%L, %L, 'accepted')$$, pg_temp.u(1), (SELECT id FROM act2)),
    'P0001', NULL, 'an expired proposal cannot be accepted (ACTION_EXPIRED)');
SELECT throws_ok(format($$SELECT pg_temp.resolve(%L, %L, 'logged')$$, pg_temp.u(1), (SELECT id FROM act2)),
    '22023', NULL, 'only accepted / dismissed');

-- ===== Context sent to the model =====
SELECT pg_temp.act(pg_temp.u(1));
CREATE TEMP TABLE ctx AS SELECT ai.fn_rin_context(pg_temp.u(1))::text AS t;
SELECT doesnt_match((SELECT t FROM ctx), 'Secret Name', 'the context never contains the user''s name');
SELECT doesnt_match((SELECT t FROM ctx), '@example.test', 'nor an email');
SELECT doesnt_match((SELECT t FROM ctx), 'rin.user', 'nor a username');

-- ===== Ownership and delete =====
INSERT INTO privacy.consent_record (user_id, purpose, policy_version, granted, recorded_at)
VALUES (pg_temp.u(2), 'ai_processing', '1.0', TRUE, now());
SELECT pg_temp.act(pg_temp.u(2));
SELECT throws_ok(format($$SELECT * FROM ai.fn_messages(%L, %L, NULL, 10)$$, pg_temp.u(2), (SELECT id FROM chat)),
    '42501', NULL, 'another user cannot read the chat');
SELECT throws_ok(format($$SELECT pg_temp.say(%L, %L, uuidv7(), 'hello')$$, pg_temp.u(2), (SELECT id FROM chat)),
    '42501', NULL, 'nor write into it');
SELECT throws_ok(format($$CALL ai.pr_delete_conversation(%L, %L)$$, pg_temp.u(2), (SELECT id FROM chat)),
    '42501', NULL, 'nor delete it');
SELECT pg_temp.act(pg_temp.u(1));
SELECT lives_ok(format($$CALL ai.pr_delete_conversation(%L, %L)$$, pg_temp.u(1), (SELECT id FROM chat)), 'the owner deletes it');
SELECT is((SELECT count(*)::int FROM ai.fn_conversations(pg_temp.u(1), NULL, NULL, 50)), 0, 'a deleted chat is no longer listed');

SELECT * FROM finish();
ROLLBACK;
