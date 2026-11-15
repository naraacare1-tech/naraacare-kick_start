import 'package:naraacare/core/network/api_client.dart';
import 'package:uuid/uuid.dart';

/// Avatars a member can share with a circle (doc 04 section 2.9).
enum AvatarType { hydration, nutrition, sleep }

AvatarType? _avatar(Object? code) => switch (code) {
  'hydration' => AvatarType.hydration,
  'nutrition' => AvatarType.nutrition,
  'sleep' => AvatarType.sleep,
  _ => null,
};

DateTime? _time(Object? v) => v == null ? null : DateTime.parse(v as String);

List<Map<String, dynamic>> _items(Object? json) =>
    ((json! as Map<String, dynamic>)['items'] as List)
        .cast<Map<String, dynamic>>();

/// A user's public card (username, initial and avatar code; names only
/// between connected people). Everything here is plain text from the API
/// and is shown with Text widgets only.
class PersonCard {
  const new({
    required this.userId,
    required this.username,
    required this.initial,
    this.displayName,
  });

  factory fromJson(Map<String, dynamic> json) => PersonCard(
    userId: json['user_id'] as String,
    username: json['username'] as String?,
    initial: (json['display_initial'] as String?) ?? '?',
    displayName: json['display_name'] as String?,
  );

  final String userId;
  final String? username;
  final String initial;
  final String? displayName;

  String get handle => username == null ? initial : '@$username';
}

/// none | connected | incoming | outgoing (people search, connections).
enum ConnectionStatus { none, connected, incoming, outgoing }

ConnectionStatus _connection(Object? v) => switch (v) {
  'connected' => ConnectionStatus.connected,
  'incoming' => ConnectionStatus.incoming,
  'outgoing' => ConnectionStatus.outgoing,
  _ => ConnectionStatus.none,
};

class Connection {
  const new({required this.id, required this.person, required this.state});

  factory fromJson(Map<String, dynamic> json) => Connection(
    id: json['connection_id'] as String,
    person: PersonCard.fromJson(json),
    state: _connection(json['status']),
  );

  final String id;
  final PersonCard person;
  final ConnectionStatus state;
}

class SearchResult {
  const new({required this.person, required this.state});

  factory fromJson(Map<String, dynamic> json) => SearchResult(
    person: PersonCard.fromJson(json),
    state: _connection(json['connection_status']),
  );

  final PersonCard person;
  final ConnectionStatus state;
}

/// "Your Circles" row.
class CircleSummary {
  const new({
    required this.id,
    required this.name,
    required this.wallpaper,
    required this.memberCount,
    required this.isAdmin,
    required this.updatesToday,
    required this.unread,
  });

  factory fromJson(Map<String, dynamic> json) => CircleSummary(
    id: json['circle_id'] as String,
    name: json['name'] as String,
    wallpaper: json['wallpaper_code'] as String?,
    memberCount: (json['member_count'] as num).toInt(),
    isAdmin: json['my_role'] == 'admin',
    updatesToday: (json['updates_today'] as num?)?.toInt() ?? 0,
    unread: (json['unread'] as num?)?.toInt() ?? 0,
  );

  final String id;
  final String name;
  final String? wallpaper;
  final int memberCount;
  final bool isAdmin;
  final int updatesToday;
  final int unread;
}

/// Per-circle notification switches (Figma "Notification Settings").
class CirclePrefs {
  const new(this.values);

  static const keys = [
    'member_join_leave',
    'circle_updates',
    'goal_completions',
    'avatar_updates',
    'mentions',
    'new_messages',
  ];

  final Map<String, bool> values;

  CirclePrefs copyWith(String key, {required bool value}) =>
      CirclePrefs({...values, key: value});
}

class MemberPreview {
  const new({required this.person, required this.isAdmin});

  final PersonCard person;
  final bool isAdmin;
}

class LastMessage {
  const new({required this.senderId, required this.body, required this.at});

  final String senderId;

  /// null when the message was deleted.
  final String? body;
  final DateTime at;
}

/// Circle home (GET /circles/{id}).
class CircleDetail {
  const new({
    required this.id,
    required this.name,
    required this.wallpaper,
    required this.memberCount,
    required this.isAdmin,
    required this.myShares,
    required this.prefs,
    required this.members,
    required this.lastMessage,
  });

  factory fromJson(Map<String, dynamic> json) {
    final last = json['last_message'] as Map<String, dynamic>?;
    return CircleDetail(
      id: json['circle_id'] as String,
      name: json['name'] as String,
      wallpaper: json['wallpaper_code'] as String?,
      memberCount: (json['member_count'] as num).toInt(),
      isAdmin: json['my_role'] == 'admin',
      myShares: {
        for (final s in (json['my_shares'] as List? ?? const [])) ?_avatar(s),
      },
      prefs: CirclePrefs({
        for (final e
            in ((json['preferences'] as Map<String, dynamic>?) ?? const {})
                .entries)
          e.key: e.value == true,
      }),
      members: [
        for (final m
            in (json['members_preview'] as List? ?? const [])
                .cast<Map<String, dynamic>>())
          MemberPreview(
            person: PersonCard.fromJson(m),
            isAdmin: m['role'] == 'admin',
          ),
      ],
      lastMessage: last == null
          ? null
          : LastMessage(
              senderId: last['sender_id'] as String,
              body: last['body'] as String?,
              at: DateTime.parse(last['created_at'] as String),
            ),
    );
  }

  final String id;
  final String name;
  final String? wallpaper;
  final int memberCount;
  final bool isAdmin;
  final Set<AvatarType> myShares;
  final CirclePrefs prefs;
  final List<MemberPreview> members;
  final LastMessage? lastMessage;
}

enum MemberStatus { active, invited, other }

class CircleMember {
  const new({
    required this.person,
    required this.isAdmin,
    required this.status,
    required this.joinedAt,
    required this.shares,
  });

  factory fromJson(Map<String, dynamic> json) => CircleMember(
    person: PersonCard.fromJson(json),
    isAdmin: json['role'] == 'admin',
    status: switch (json['status']) {
      'active' => MemberStatus.active,
      'invited' || 'maybe_later' => MemberStatus.invited,
      _ => MemberStatus.other,
    },
    joinedAt: _time(json['joined_at']),
    shares: {
      for (final s in (json['shares'] as List? ?? const [])) ?_avatar(s),
    },
  );

  final PersonCard person;
  final bool isAdmin;
  final MemberStatus status;
  final DateTime? joinedAt;
  final Set<AvatarType> shares;
}

/// shared | not_shared | requires_star (GET .../members/{id}/avatars).
enum AvatarVisibility { shared, notShared, requiresStar }

class MemberAvatar {
  const new({
    required this.type,
    required this.visibility,
    required this.state,
  });

  factory fromJson(Map<String, dynamic> json) => MemberAvatar(
    type: _avatar(json['avatar_type']) ?? AvatarType.hydration,
    visibility: switch (json['visibility']) {
      'shared' => AvatarVisibility.shared,
      'requires_star' => AvatarVisibility.requiresStar,
      _ => AvatarVisibility.notShared,
    },
    state: (json['state'] as Map<String, dynamic>?) ?? const {},
  );

  final AvatarType type;
  final AvatarVisibility visibility;

  /// Today's values from the server (e.g. consumed_ml, goal_ml, pct).
  final Map<String, dynamic> state;
}

/// A Recent Updates row (logged / goal_completed / joined / left).
class FeedEvent {
  const new({
    required this.id,
    required this.at,
    required this.actor,
    required this.type,
    required this.avatar,
    required this.summary,
  });

  factory fromJson(Map<String, dynamic> json) => FeedEvent(
    id: json['event_id'] as String,
    at: DateTime.parse(json['occurred_at'] as String),
    actor: PersonCard.fromJson({...json, 'user_id': json['actor_id']}),
    type: json['event_type'] as String,
    avatar: _avatar(json['avatar_type']),
    summary: (json['summary'] as Map<String, dynamic>?) ?? const {},
  );

  final String id;
  final DateTime at;
  final PersonCard actor;
  final String type;
  final AvatarType? avatar;
  final Map<String, dynamic> summary;
}

class ChatMessage {
  const new({
    required this.id,
    required this.at,
    required this.sender,
    required this.body,
    required this.deleted,
    required this.mentions,
  });

  factory fromJson(Map<String, dynamic> json) => ChatMessage(
    id: json['message_id'] as String,
    at: DateTime.parse(json['created_at'] as String),
    sender: PersonCard.fromJson({...json, 'user_id': json['sender_id']}),
    body: json['body'] as String?,
    deleted: json['deleted'] == true,
    mentions: [
      for (final m in (json['mention_user_ids'] as List? ?? const []))
        m as String,
    ],
  );

  final String id;
  final DateTime at;
  final PersonCard sender;
  final String? body;
  final bool deleted;
  final List<String> mentions;
}

class CircleInvite {
  const new({
    required this.circleId,
    required this.name,
    required this.wallpaper,
    required this.memberCount,
    required this.inviter,
  });

  factory fromJson(Map<String, dynamic> json) => CircleInvite(
    circleId: json['circle_id'] as String,
    name: json['name'] as String,
    wallpaper: json['wallpaper_code'] as String?,
    memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    inviter: json['inviter_username'] as String?,
  );

  final String circleId;
  final String name;
  final String? wallpaper;
  final int memberCount;
  final String? inviter;
}

class InAppNotification {
  const new({
    required this.id,
    required this.at,
    required this.template,
    required this.params,
    required this.read,
    this.circleId,
  });

  factory fromJson(Map<String, dynamic> json) => InAppNotification(
    id: json['notification_id'] as String,
    at: DateTime.parse(json['created_at'] as String),
    template: json['template_code'] as String,
    params: (json['params'] as Map<String, dynamic>?) ?? const {},
    read: json['read_at'] != null,
    circleId: json['circle_id'] as String?,
  );

  final String id;

  /// The circle the notification belongs to (null for personal ones).
  final String? circleId;
  final DateTime at;
  final String template;
  final Map<String, dynamic> params;
  final bool read;
}

/// REST calls for connections, circles and chat (doc 04 sections 2.8-2.9).
/// The API enforces membership, blocks and limits; ids come from the server.
class CircleApi {
  const new(this.api);

  final ApiClient api;
  static const _uuid = Uuid();

  // -------------------------------------------------------------- people
  Future<List<SearchResult>> search(String query) async => [
    for (final j in _items(await api.get('people/search', query: {'q': query})))
      SearchResult.fromJson(j),
  ];

  Future<List<PersonCard>> suggestions() async => [
    for (final j in _items(await api.get('people/suggestions')))
      PersonCard.fromJson(j),
  ];

  Future<List<Connection>> connections() async => [
    for (final j in _items(await api.get('connections')))
      Connection.fromJson(j),
  ];

  Future<void> requestConnection(String username) =>
      api.post('connections/requests', body: {'username': username});

  Future<void> respondConnection(String id, {required bool accept}) =>
      api.post('connections/requests/$id/${accept ? 'accept' : 'decline'}');

  Future<void> removeConnection(String id) => api.delete('connections/$id');

  Future<void> block(String userId) =>
      api.post('blocks', body: {'user_id': userId});

  // -------------------------------------------------------------- circles
  Future<List<CircleSummary>> circles() async => [
    for (final j in _items(await api.get('circles'))) CircleSummary.fromJson(j),
  ];

  Future<CircleDetail> createCircle({
    required String name,
    required List<String> inviteeIds,
    required Set<AvatarType> shares,
  }) async => CircleDetail.fromJson(
    (await api.post(
          'circles',
          body: {
            'name': name,
            'invitee_user_ids': inviteeIds,
            'shared_avatars': [for (final s in shares) s.name],
          },
        ))!
        as Map<String, dynamic>,
  );

  Future<CircleDetail> detail(String id) async => CircleDetail.fromJson(
    (await api.get('circles/$id'))! as Map<String, dynamic>,
  );

  Future<void> updateCircle(String id, {String? name, String? wallpaper}) =>
      api.patch(
        'circles/$id',
        body: {'name': ?name, 'wallpaper_code': ?wallpaper},
      );

  Future<List<CircleMember>> members(String id, {String? query}) async => [
    for (final j in _items(
      await api.get('circles/$id/members', query: {'q': ?query}),
    ))
      CircleMember.fromJson(j),
  ];

  Future<void> inviteMembers(String id, List<String> userIds) =>
      api.post('circles/$id/members', body: {'user_ids': userIds});

  Future<void> removeMember(String id, String userId) =>
      api.delete('circles/$id/members/$userId');

  Future<void> setRole(String id, String userId, {required bool admin}) =>
      api.put(
        'circles/$id/members/$userId/role',
        body: {'role': admin ? 'admin' : 'member'},
      );

  Future<List<MemberAvatar>> memberAvatars(String id, String userId) async => [
    for (final j in _items(
      await api.get('circles/$id/members/$userId/avatars'),
    ))
      MemberAvatar.fromJson(j),
  ];

  Future<void> leave(String id) => api.post('circles/$id/leave');

  Future<void> updateShares(String id, Set<AvatarType> shares) => api.put(
    'circles/$id/shares',
    body: {
      'shared_avatars': [for (final s in shares) s.name],
    },
  );

  /// Shares today's avatar card inside NaraaCare only (V029): own circles
  /// and connections. The server reads the values; only ids are sent.
  Future<void> shareAvatar(
    AvatarType avatar, {
    required Iterable<String> circleIds,
    required Iterable<String> userIds,
  }) => api.post(
    'avatar-shares',
    body: {
      'avatar_type': avatar.name,
      'circle_ids': circleIds.toList(),
      'user_ids': userIds.toList(),
    },
  );

  Future<List<FeedEvent>> feed(String id, {int limit = 30}) async => [
    for (final j in _items(
      await api.get('circles/$id/feed', query: {'limit': limit}),
    ))
      FeedEvent.fromJson(j),
  ];

  Future<void> setPrefs(String id, CirclePrefs prefs) =>
      api.put('circles/$id/notification-settings', body: prefs.values);

  // -------------------------------------------------------------- invites
  Future<List<CircleInvite>> invites() async => [
    for (final j in _items(await api.get('circle-invites')))
      CircleInvite.fromJson(j),
  ];

  Future<void> acceptInvite(String circleId, Set<AvatarType> shares) =>
      api.post(
        'circle-invites/$circleId/accept',
        body: {
          'shared_avatars': [for (final s in shares) s.name],
        },
      );

  Future<void> declineInvite(String circleId, {bool later = false}) =>
      api.post('circle-invites/$circleId/${later ? 'later' : 'decline'}');

  /// The link is returned once; the server keeps only its hash.
  Future<String> createInviteLink(String circleId) async =>
      ((await api.post('circles/$circleId/invite-links', body: const {}))!
              as Map<String, dynamic>)['url']
          as String;

  Future<CircleInvite> resolveInviteLink(String token) async {
    final json =
        (await api.post('invite-links/resolve', body: {'token': token}))!
            as Map<String, dynamic>;
    return CircleInvite.fromJson(json);
  }

  // -------------------------------------------------------------- chat
  Future<List<ChatMessage>> messages(String id, {DateTime? before}) async => [
    for (final j in _items(
      await api.get(
        'circles/$id/messages',
        query: {'before': ?before?.toUtc().toIso8601String()},
      ),
    ))
      ChatMessage.fromJson(j),
  ];

  Future<ChatMessage> send(
    String id,
    String body,
    List<String> mentionIds, {
    String? clientMessageId,
  }) async => ChatMessage.fromJson(
    (await api.post(
          'circles/$id/messages',
          body: {
            'client_message_id': clientMessageId ?? _uuid.v4(),
            'body': body,
            'mention_user_ids': mentionIds,
          },
        ))!
        as Map<String, dynamic>,
  );

  Future<void> deleteMessage(String id, String messageId) =>
      api.delete('circles/$id/messages/$messageId');

  Future<void> markRead(String id) => api.post('circles/$id/messages/read');

  // ------------------------------------------------------ notifications
  Future<List<InAppNotification>> notifications({String? circleId}) async => [
    for (final j in _items(
      await api.get('notifications', query: {'circle_id': ?circleId}),
    ))
      InAppNotification.fromJson(j),
  ];

  Future<void> markNotificationsRead({String? circleId}) =>
      api.post('notifications/read', body: {'circle_id': ?circleId});

  /// A single-use ticket that opens the realtime socket within 30 s.
  Future<String> realtimeTicket() async =>
      ((await api.post('realtime/ticket'))! as Map<String, dynamic>)['ticket']
          as String;
}
