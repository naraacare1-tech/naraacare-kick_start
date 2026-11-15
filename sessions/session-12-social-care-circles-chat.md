# Session 12 — Connections, Care Circles, Chat, Feed and Social Notifications

## Goal and scope
Build the social layer: usernames (enforced), people search, connections (request/accept/decline/remove), blocking, Care Circles (create, invite by username or link, accept/decline/maybe later, ≥ 1 avatar shared, sleep STAR→STAR), member avatars, Recent Updates feed, real-time chat with @mentions, circle settings (rename, wallpaper, notification toggles, manage/remove members, leave with admin succession), push + in-app notifications for social events.

**In:** `social` schema (tables + functions/procedures), `/people/*`, `/connections/*`, `/blocks`, `/circles/*`, `/circle-invites/*`, `/invite-links/*`, `/realtime/ticket`, WebSocket, social notifications; mobile `features/care_circle`, `features/connections`.
**Out:** notification centre UI polish (S14).

## Prerequisites
S05 (username), S08–S11 (avatars + tier). Decisions/defaults: OQ-24, OQ-35, OQ-36, OQ-41.

## Files to create / modify

### naraacare-database
```
migrations/V0xx__social_tables.sql          # connection, user_block, care_circle, circle_member, circle_share, circle_invite_link, chat_message (P), chat_mention, activity_event (P)
migrations/V0xx__notify_circle_prefs.sql    # notify.circle_notification_preference
migrations/V0xx__social_rls_partitions.sql  # RLS policies (member-based), ops.partition_config rows
tables/ indexes/ (canonical files)
functions/R__20_social.fn_can_view.sql (owner, viewer, avatar_type) fn_people_search.sql fn_suggestions.sql fn_connections.sql
functions/R__20_social.fn_circles_for_user.sql fn_circle_detail.sql fn_circle_members.sql fn_member_avatars.sql fn_circle_feed.sql fn_messages.sql fn_pending_invites.sql
procedures/R__30_social.pr_request_connection.sql pr_respond_connection.sql pr_remove_connection.sql pr_block.sql pr_unblock.sql
procedures/R__30_social.pr_create_circle.sql (lock, ≤ 50, ≥ 1 share, sleep STAR) pr_invite_members.sql pr_respond_invite.sql pr_update_shares.sql
procedures/R__30_social.pr_leave_circle.sql (admin succession, empty → soft delete) pr_remove_member.sql pr_update_circle.sql pr_delete_circle.sql
procedures/R__30_social.pr_create_invite_link.sql pr_resolve_invite_link.sql pr_revoke_invite_link.sql
procedures/R__30_social.pr_post_message.sql (idempotent, mentions only of members) pr_delete_message.sql
procedures/R__30_notify.pr_create_notification.sql pr_set_circle_prefs.sql
tests/600_social_*.sql
```
Also update S08/S09/S10 procedures to emit `social.activity_event` (logged / goal_completed).

### naraacare-backend
```
app/api/v1/routers/people.py connections.py circles.py chat.py realtime.py notifications.py (circle filter)
app/schemas/social.py chat.py
app/domain/social/service.py feed.py mentions.py
app/realtime/ws_manager.py   # WebSocket auth via ticket (Redis, 30 s, single use), per-installation connection, Redis pub/sub fan-out, heartbeats
app/integrations/fcm.py (social templates; mentions push default on; no message body in push)
app/workers/jobs/social_notifications.py
tests/integration/test_connections.py test_circles.py test_chat_ws.py test_feed_visibility.py
tests/security/test_social_authz.py
```

### naraacare-mobile
```
lib/features/connections/presentation/screens/{connections, find_people}.dart
lib/features/care_circle/presentation/screens/{your_circles, create_circle, add_members, choose_shares, circle_home, circle_chat, invite_detail, all_members, member_profile, circle_notifications, circle_settings, circle_profile, manage_members, member_admin, circle_notification_settings}.dart
lib/features/care_circle/data/realtime_client.dart (reconnect with backoff, ticket refresh)
lib/features/care_circle/presentation/widgets/{mention_text_field, mention_rendering (plain Text spans), member_strip, feed_item, share_toggle_row}.dart
test/features/care_circle/** test/features/connections/**
```

## Step-by-step tasks
1. Tables, RLS (membership-based policies via helper functions), partitions, indexes per doc 05 §5.6.
2. Username gate (`USERNAME_REQUIRED` → app shows the username sheet).
3. People search (prefix ≥ 3, blocked hidden both ways), suggestions, connection lifecycle, block/unblock.
4. Circles: create (name, invitees, shares), invites (Accept with share selection / Decline / Maybe Later), invite links (token 32 bytes random, hashed; 7 days; max uses; revoke), deep-link flow (install → sign up → onboarding → username → choose shares → circle home).
5. Visibility: `fn_member_avatars` returns only shared avatars' current summaries; sleep visible only if both owner and viewer are STAR; otherwise flags `not_shared` / `requires_star`.
6. Feed: fan-out-on-read from `activity_event` for members sharing that avatar since `shared_since`; cursor pagination.
7. Chat: REST send/list + WS push; mentions resolved to member user ids (usernames rendered as plain text spans, not links); delete own message; admin delete; rate limit 30/min; body encrypted at rest.
8. Notifications: goal completions, joins/leaves, mentions, admin changes → in-app rows + push per prefs; logs → feed only (DOC §5).
9. Settings: rename, wallpaper, notification toggles, manage members, remove member, leave (confirm dialog) with succession.
10. Downgrade handling: sleep shares hidden for non-STAR (blurred card "Sleep avatar is available with STAR plan").

## DB objects
Tables listed + functions/procedures; `notify.circle_notification_preference`.

## API endpoints
Doc 04 §2.8 and §2.9 (all), `GET /notifications?circle_id=`.

## Screens (Figma frames)
`Your Circles` (empty + list + Invites), username sheet, `Create a Circle`, `Add Members` (People on NaraaCare / Invite Link), `Share with Gym Buddies` (STANDARD & STAR variants), `Care Circle 5/Home page`, circle chat, invite detail (in-app + link flow), `All Members`, member profile (`@sahil.123` View Profile: water / not shared / sleep STAR), circle `Notifications`, circle `Settings` + leave dialog, circle `Profile` (wallpaper + name), `Manage Members`, `Member`, circle `Notification Settings`, `Connections` (My Connections / Find People / Invites / Suggested).

## Security checks
BOLA on every circle/message/member route (membership enforced in DB functions + RLS); blocked-user enforcement; mention injection (only member ids accepted; rendered as plain text); chat encryption at rest; WS auth via short single-use ticket (no JWT in URL); WS message size limit 8 KB and rate limit; invite token hashed, expiring, revocable; push without message bodies or health values; harassment controls (block, admin remove, delete).

## Input-validation checklist
| Field | App validator | Max | API type | DB |
|---|---|---|---|---|
| Circle name | `shortText(50)` | 50 | SafeShortText(50) | safe_text(50) |
| People / member search | `usernameSearch()` | 64 | SafeSearchQuery | — |
| Username (connect) | `username()` | 30 | SafeUsername | common.username |
| Chat message | `chatMessage(2000)` | 2000 | SafeChatMessage | ciphertext (validated pre-encryption) |
| Invite token (deep link) | `deep_link_validator` | 64 | SafeOpaqueToken(64) | blind index |
| WS client frames | JSON schema (type enum, circle_id UUID) | 8 KB | Pydantic | — |
- [ ] Payload sweep includes chat + circle fields; WS frames fuzzed with payloads (rejected/ignored, connection kept safe).

## Tests to write
Circle cap 50 under concurrent accepts; ≥ 1 share enforced; sleep share STAR-only + viewer STAR-only; unshare hides past feed items; admin succession; removed member loses access immediately (REST + WS); blocked users can't search/invite/mention; invite link expiry/max uses/revoke; message idempotency; mention of non-member rejected; WS ticket single use + expiry; push payload content check; IDOR suite for all circle routes with a non-member; widget tests for all screens; E2E two-device chat.

## Acceptance criteria / Definition of done
- [ ] The full DOC §5 flow works on two devices (create → invite by username and by link → accept with shares → chat with @mention → feed → leave).
- [ ] Non-members get 404 on every circle resource.
- [ ] Sharing rules (≥ 1, sleep STAR→STAR, downgrade blur) enforced server-side.
- [ ] Chat delivery p95 ≤ 500 ms on staging.
- [ ] Notifications vs feed separation as specified; push texts generic.
- [ ] 3-layer payload tests green for all new fields.

## Estimated effort
12–14 developer-days.
