-- Care Circles, connections, chat and invite links (Session 12; doc 04 sections 2.8-2.9, doc 06
-- section 7, OQ-35, OQ-36): username required, 1..3 shares with Sleep STAR-only, the 50-seat cap,
-- invites must be accepted, removed members lose access at once, admin succession, blocks (no
-- search/invite/mention), idempotent messages with member-only mentions, invite link expiry, use
-- limit and revocation.
BEGIN;
SELECT no_plan();

CREATE FUNCTION pg_temp.u(n integer) RETURNS uuid LANGUAGE sql AS $$
    SELECT ('0192f000-0000-7000-8000-' || lpad(to_hex(24576 + n), 12, '0'))::uuid
$$;
INSERT INTO auth.user_account (id, email, status)
SELECT pg_temp.u(n), 'c' || n || '@example.test', 'active' FROM generate_series(1, 60) AS n;
INSERT INTO app.user_profile (user_id, onboarding_step, onboarding_completed_at, username)
SELECT pg_temp.u(n), 6, now(), CASE WHEN n = 60 THEN NULL ELSE 'circle.user' || n END
FROM generate_series(1, 60) AS n;
-- u1 is STAR (may share Sleep).
INSERT INTO billing.entitlement_grant (user_id, tier_code, source, starts_at, ends_at)
VALUES (pg_temp.u(1), 'star', 'promo', now() - interval '1 day', now() + interval '30 days');

CREATE FUNCTION pg_temp.act(p_user uuid) RETURNS void LANGUAGE sql AS $$
    SELECT set_config('app.user_id', p_user::text, TRUE)
$$;
CREATE FUNCTION pg_temp.create_circle(p_user uuid, p_invitees uuid[], p_shares text[]) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE c uuid; n integer;
BEGIN
    PERFORM pg_temp.act(p_user);
    CALL social.pr_create_circle(p_user, 'Family', p_invitees, p_shares, c, n);
    RETURN c;
END
$$;
CREATE FUNCTION pg_temp.respond(p_user uuid, p_circle uuid, p_action text, p_shares text[] DEFAULT ARRAY['hydration'])
RETURNS text LANGUAGE plpgsql AS $$
DECLARE s text;
BEGIN
    PERFORM pg_temp.act(p_user);
    CALL social.pr_respond_invite(p_user, p_circle, p_action, p_shares, s);
    RETURN s;
END
$$;
CREATE FUNCTION pg_temp.member(p_circle uuid, p_user uuid) RETURNS text LANGUAGE sql AS $$
    SELECT status || '/' || role FROM social.circle_member WHERE circle_id = p_circle AND user_id = p_user
$$;
CREATE FUNCTION pg_temp.post(p_user uuid, p_circle uuid, p_client uuid, p_body text, p_mentions uuid[] DEFAULT '{}')
RETURNS text LANGUAGE plpgsql AS $$
DECLARE m uuid; t timestamptz; s text;
BEGIN
    PERFORM pg_temp.act(p_user);
    CALL social.pr_post_message(p_user, p_circle, p_client, p_body, p_mentions, m, t, s);
    RETURN s;
END
$$;

CREATE FUNCTION pg_temp.remove(p_admin uuid, p_circle uuid, p_member uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.act(p_admin); CALL social.pr_remove_member(p_admin, p_circle, p_member); END $$;
CREATE FUNCTION pg_temp.leave(p_user uuid, p_circle uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.act(p_user); CALL social.pr_leave_circle(p_user, p_circle); END $$;
CREATE FUNCTION pg_temp.invite(p_admin uuid, p_circle uuid, p_user uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN PERFORM pg_temp.act(p_admin); CALL social.pr_invite_members(p_admin, p_circle, ARRAY[p_user], n); RETURN n; END $$;
CREATE FUNCTION pg_temp.request(p_user uuid, p_username text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE c uuid; st text;
BEGIN PERFORM pg_temp.act(p_user); CALL social.pr_request_connection(p_user, p_username, c, st); RETURN st; END $$;
CREATE FUNCTION pg_temp.new_link(p_admin uuid, p_circle uuid, p_token text, p_max smallint) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE l uuid; e timestamptz;
BEGIN PERFORM pg_temp.act(p_admin); CALL social.pr_create_invite_link(p_admin, p_circle, sha256(p_token::bytea), p_max, l, e); RETURN l; END $$;
CREATE FUNCTION pg_temp.revoke_link(p_admin uuid, p_circle uuid, p_link uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN PERFORM pg_temp.act(p_admin); CALL social.pr_revoke_invite_link(p_admin, p_circle, p_link); END $$;

-- ===== Username and shares =====
SELECT throws_ok(
    $$SELECT pg_temp.create_circle(pg_temp.u(60), '{}', ARRAY['hydration'])$$,
    'P0001', NULL, 'a user without a username cannot create a circle (USERNAME_REQUIRED)'
);
SELECT throws_ok(
    $$SELECT pg_temp.create_circle(pg_temp.u(2), '{}', '{}')$$,
    '22023', NULL, 'at least one shared avatar is required'
);
SELECT throws_ok(
    $$SELECT pg_temp.create_circle(pg_temp.u(2), '{}', ARRAY['sleep'])$$,
    'P0001', NULL, 'a STANDARD member cannot share Sleep'
);
CREATE TEMP TABLE k AS SELECT pg_temp.create_circle(pg_temp.u(1), ARRAY[pg_temp.u(2), pg_temp.u(3)], ARRAY['sleep', 'hydration']) AS c;
SELECT is(pg_temp.member((SELECT c FROM k), pg_temp.u(1)), 'active/admin', 'the creator is the admin');
SELECT is(pg_temp.member((SELECT c FROM k), pg_temp.u(2)), 'invited/member', 'adding someone creates an invite, not a membership');

-- ===== Invites and access =====
SELECT throws_ok(
    format($$SELECT social.fn_circle_detail(%L, %L)$$, pg_temp.u(2), (SELECT c FROM k)),
    '42501', NULL, 'an invited (not yet accepted) user cannot read the circle'
);
SELECT pg_temp.respond(pg_temp.u(2), (SELECT c FROM k), 'accept');
SELECT pg_temp.respond(pg_temp.u(3), (SELECT c FROM k), 'accept');
SELECT is(pg_temp.member((SELECT c FROM k), pg_temp.u(2)), 'active/member', 'accepting with a share makes a member');
SELECT pg_temp.act(pg_temp.u(2));
SELECT lives_ok(format($$SELECT social.fn_circle_detail(%L, %L)$$, pg_temp.u(2), (SELECT c FROM k)), 'a member reads the circle');
SELECT pg_temp.act(pg_temp.u(9));
SELECT throws_ok(
    format($$SELECT social.fn_circle_detail(%L, %L)$$, pg_temp.u(9), (SELECT c FROM k)),
    '42501', NULL, 'an outsider gets 404'
);

-- Removed members lose access at once.
SELECT pg_temp.remove(pg_temp.u(1), (SELECT c FROM k), pg_temp.u(3));
SELECT pg_temp.act(pg_temp.u(3));
SELECT throws_ok(
    format($$SELECT social.fn_messages(%L, %L, NULL, 10)$$, pg_temp.u(3), (SELECT c FROM k)),
    '42501', NULL, 'a removed member can no longer read messages'
);
SELECT throws_ok(
    format($$SELECT pg_temp.post(%L, %L, uuidv7(), 'still here?')$$, pg_temp.u(3), (SELECT c FROM k)),
    '42501', NULL, 'a removed member can no longer post'
);
SELECT pg_temp.act(pg_temp.u(2));
SELECT throws_ok(
    format($$SELECT pg_temp.remove(%L, %L, %L)$$, pg_temp.u(2), (SELECT c FROM k), pg_temp.u(1)),
    'P0001', NULL, 'only admins remove members (ADMIN_REQUIRED)'
);

-- ===== Messages =====
SELECT is(pg_temp.post(pg_temp.u(2), (SELECT c FROM k), '0192f000-0000-7000-8000-0000000060c1', 'Drink water!'), 'created',
    'a member posts');
SELECT is(pg_temp.post(pg_temp.u(2), (SELECT c FROM k), '0192f000-0000-7000-8000-0000000060c1', 'Drink water!'), 'duplicate',
    'the same client message id is not posted twice');
SELECT throws_ok(
    format($$SELECT pg_temp.post(%L, %L, uuidv7(), 'hi', ARRAY[%L]::uuid[])$$, pg_temp.u(2), (SELECT c FROM k), pg_temp.u(9)),
    '22023', NULL, 'mentioning a non-member is refused (MENTION_INVALID)'
);
SELECT throws_ok(
    format($$SELECT pg_temp.post(%L, %L, uuidv7(), '<b>hi</b>')$$, pg_temp.u(2), (SELECT c FROM k)),
    '23514', NULL, 'markup in a message is refused by safe_text'
);
SELECT is(
    (SELECT count(*)::int FROM notify.notification AS n
     WHERE n.user_id = pg_temp.u(1) AND n.params::text LIKE '%Drink water%'),
    0, 'notifications never carry the message text'
);

-- ===== Admin succession =====
SELECT pg_temp.leave(pg_temp.u(1), (SELECT c FROM k));
SELECT is(pg_temp.member((SELECT c FROM k), pg_temp.u(2)), 'active/admin', 'the earliest remaining member becomes admin');
SELECT is((SELECT count(*)::int FROM social.circle_share WHERE circle_id = (SELECT c FROM k) AND user_id = pg_temp.u(1)), 0,
    'a member who leaves stops sharing');
SELECT pg_temp.leave(pg_temp.u(2), (SELECT c FROM k));
SELECT isnt((SELECT deleted_at FROM social.care_circle WHERE id = (SELECT c FROM k)), NULL, 'an empty circle is soft-deleted');

-- ===== The 50-seat cap =====
CREATE TEMP TABLE big AS SELECT pg_temp.create_circle(
    pg_temp.u(4), ARRAY(SELECT pg_temp.u(n) FROM generate_series(5, 52) AS n), ARRAY['hydration']
) AS c;
SELECT is((SELECT social.fn_seats_taken((SELECT c FROM big)))::int, 49, 'creator + 48 invites hold 49 seats');
SELECT lives_ok(format($$SELECT pg_temp.invite(%L, %L, %L)$$, pg_temp.u(4), (SELECT c FROM big), pg_temp.u(53)),
    'the 50th seat can be filled');
SELECT throws_ok(
    format($$SELECT pg_temp.invite(%L, %L, %L)$$, pg_temp.u(4), (SELECT c FROM big), pg_temp.u(54)),
    'P0001', NULL, 'the 51st is refused (CIRCLE_FULL)'
);

-- ===== Blocks =====
SELECT pg_temp.act(pg_temp.u(55));
CALL social.pr_block('0192f000-0000-7000-8000-000000006037', '0192f000-0000-7000-8000-000000006038');
SELECT pg_temp.act(pg_temp.u(56));
SELECT is(
    (SELECT count(*)::int FROM social.fn_people_search(pg_temp.u(56), 'circle.user55') AS r),
    0, 'a blocked user does not find the blocker'
);
SELECT throws_ok(
    $$SELECT pg_temp.request(pg_temp.u(56), 'circle.user55')$$,
    '42501', NULL, 'a blocked user cannot send a connection request (404, no probing)'
);
CREATE TEMP TABLE blk AS SELECT pg_temp.create_circle(pg_temp.u(56), ARRAY[pg_temp.u(55)], ARRAY['hydration']) AS c;
SELECT is(pg_temp.member((SELECT c FROM blk), pg_temp.u(55)), NULL, 'inviting someone who blocked you is silently skipped');

-- ===== Invite links =====
CREATE TEMP TABLE lnk AS SELECT pg_temp.create_circle(pg_temp.u(57), '{}', ARRAY['hydration']) AS c;
CREATE TEMP TABLE link1 AS SELECT pg_temp.new_link(pg_temp.u(57), (SELECT c FROM lnk), 'token-one', 1::smallint) AS id;
ALTER TABLE link1 ADD COLUMN expires_at timestamptz;
UPDATE link1 SET expires_at = (SELECT l.expires_at FROM social.circle_invite_link AS l WHERE l.id = link1.id);
SELECT ok((SELECT expires_at FROM link1) BETWEEN now() + interval '6 days 23 hours' AND now() + interval '7 days 1 minute',
    'a link lasts 7 days');
CREATE FUNCTION pg_temp.resolve(p_user uuid, p_token text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE c uuid; s text;
BEGIN
    PERFORM pg_temp.act(p_user);
    CALL social.pr_resolve_invite_link(p_user, sha256(p_token::bytea), c, s);
    RETURN s;
END
$$;
SELECT is(pg_temp.resolve(pg_temp.u(58), 'token-one'), 'invited', 'a link turns into a normal invite');
SELECT throws_ok($$SELECT pg_temp.resolve(pg_temp.u(59), 'token-one')$$, 'P0001', NULL, 'a link with max_uses 1 is used up');
SELECT throws_ok($$SELECT pg_temp.resolve(pg_temp.u(59), 'no-such-token')$$, '42501', NULL, 'an unknown link is 404');
UPDATE social.circle_invite_link SET max_uses = 10 WHERE id = (SELECT id FROM link1);
UPDATE social.circle_invite_link SET created_at = now() - interval '8 days', expires_at = now() - interval '1 minute' WHERE id = (SELECT id FROM link1);
SELECT throws_ok($$SELECT pg_temp.resolve(pg_temp.u(59), 'token-one')$$, 'P0001', NULL, 'an expired link is refused (410)');
UPDATE social.circle_invite_link SET expires_at = now() + interval '1 day' WHERE id = (SELECT id FROM link1);
SELECT pg_temp.revoke_link(pg_temp.u(57), (SELECT c FROM lnk), (SELECT id FROM link1));
SELECT throws_ok($$SELECT pg_temp.resolve(pg_temp.u(59), 'token-one')$$, 'P0001', NULL, 'a revoked link is refused');

SELECT * FROM finish();
ROLLBACK;
