import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:uuid/uuid.dart';

/// A meal / drink Rin proposed (doc 06 section 8): nothing is logged until
/// the user taps Add to Avatar.
class RinAction {
  const new({
    required this.id,
    required this.kind,
    required this.payload,
    required this.status,
  });

  factory fromJson(Map<String, dynamic> json) => RinAction(
    id: json['action_id'] as String,
    kind: json['kind'] as String,
    payload: (json['payload'] as Map<String, dynamic>?) ?? const {},
    status: (json['status'] as String?) ?? 'pending',
  );

  final String id;

  /// meal | drink
  final String kind;
  final Map<String, dynamic> payload;

  /// pending | accepted | dismissed | expired
  final String status;

  RinAction withStatus(String value) =>
      RinAction(id: id, kind: kind, payload: payload, status: value);

  List<Map<String, dynamic>> get items => [
    for (final i in (payload['items'] as List? ?? const []))
      i as Map<String, dynamic>,
  ];

  int total(String key) =>
      ((payload['totals'] as Map<String, dynamic>?)?[key] as num?)?.toInt() ??
      0;
}

class RinMessage {
  const new({
    required this.id,
    required this.fromUser,
    required this.text,
    required this.at,
    this.action,
  });

  factory fromJson(Map<String, dynamic> json) => RinMessage(
    id: json['message_id'] as String,
    fromUser: json['role'] == 'user',
    text: json['content'] as String,
    at: DateTime.parse(json['created_at'] as String),
    action: json['action'] == null
        ? null
        : RinAction.fromJson(json['action'] as Map<String, dynamic>),
  );

  final String id;
  final bool fromUser;

  /// Plain text from the server (shown with Text widgets only).
  final String text;
  final DateTime at;
  final RinAction? action;
}

class RinConversation {
  const new({required this.id, required this.title, required this.lastAt});

  factory fromJson(Map<String, dynamic> json) => RinConversation(
    id: json['conversation_id'] as String,
    title: json['title'] as String,
    lastAt: DateTime.parse(json['last_message_at'] as String),
  );

  final String id;
  final String title;
  final DateTime lastAt;
}

class RinUsage {
  const new({required this.usedPct, required this.resetsAt});

  /// Share of the monthly limit used, one decimal (0.0 to 100.0).
  final double usedPct;
  final DateTime? resetsAt;
}

/// One server event of a reply: start, delta, action, done, error.
class RinEvent {
  const new(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;
}

/// Rin AI calls (doc 04 section 2.10). Replies stream as Server-Sent Events;
/// errors before the stream (403 UPGRADE_REQUIRED / CONSENT_REQUIRED /
/// DAILY_LIMIT_REACHED, 503) arrive as [ApiError].
class RinApi {
  const new(this.api);

  final ApiClient api;
  static const _uuid = Uuid();

  List<Map<String, dynamic>> _items(Object? json) =>
      ((json! as Map<String, dynamic>)['items'] as List)
          .cast<Map<String, dynamic>>();

  Future<RinUsage> usage() async {
    final json = (await api.get('rin/usage'))! as Map<String, dynamic>;
    return RinUsage(
      usedPct: (json['used_pct'] as num).toDouble(),
      resetsAt: json['resets_at'] == null
          ? null
          : DateTime.parse(json['resets_at'] as String),
    );
  }

  Future<List<RinConversation>> conversations({String? query}) async => [
    for (final j in _items(
      await api.get('rin/conversations', query: {'q': ?query}),
    ))
      RinConversation.fromJson(j),
  ];

  Future<List<RinMessage>> messages(String conversationId) async => [
    for (final j in _items(
      await api.get('rin/conversations/$conversationId/messages'),
    ))
      RinMessage.fromJson(j),
  ];

  Future<String> createConversation() async =>
      ((await api.post('rin/conversations'))!
              as Map<String, dynamic>)['conversation_id']
          as String;

  Future<void> deleteConversation(String id) =>
      api.delete('rin/conversations/$id');

  Future<void> deleteMemory() => api.delete('rin/memory');

  Future<void> accept(String actionId, {List<Map<String, Object?>>? items}) =>
      api.post('rin/actions/$actionId/accept', body: {'items': ?items});

  Future<void> dismiss(String actionId) =>
      api.post('rin/actions/$actionId/dismiss');

  /// Records the AI-processing consent under the current privacy policy.
  Future<void> grantAiConsent() async {
    final json = (await api.get('privacy/consents'))! as Map<String, dynamic>;
    final consents = (json['consents'] as List).cast<Map<String, dynamic>>();
    final privacy = consents
        .where((c) => c['purpose'] == 'privacy')
        .map((c) => c['policy_version'] as String)
        .firstOrNull;
    if (privacy == null) throw const ApiError(code: ApiError.unknown);
    await api.post(
      'privacy/consents',
      body: {
        'purpose': 'ai_processing',
        'policy_version': privacy,
        'granted': true,
      },
    );
  }

  /// Sends a prompt and streams the reply events.
  Stream<RinEvent> send(String conversationId, String text) async* {
    final Response<ResponseBody> response;
    try {
      response = await api.dio.post<ResponseBody>(
        'rin/conversations/$conversationId/messages',
        data: {'client_message_id': _uuid.v4(), 'content': text},
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
          receiveTimeout: const Duration(seconds: 90),
        ),
      );
    } on DioException catch (e) {
      throw await _error(e);
    }
    final buffer = StringBuffer();
    await for (final chunk in response.data!.stream.cast<List<int>>().transform(
      utf8.decoder,
    )) {
      buffer.write(chunk);
      var text = buffer.toString();
      var end = text.indexOf('\n\n');
      while (end != -1) {
        final event = _parse(text.substring(0, end));
        if (event != null) yield event;
        text = text.substring(end + 2);
        end = text.indexOf('\n\n');
      }
      buffer
        ..clear()
        ..write(text);
    }
  }

  static RinEvent? _parse(String block) {
    String? type;
    final data = StringBuffer();
    for (final line in const LineSplitter().convert(block)) {
      if (line.startsWith('event: ')) type = line.substring(7);
      if (line.startsWith('data: ')) data.write(line.substring(6));
    }
    if (type == null) return null;
    try {
      final json = jsonDecode(data.toString());
      return json is Map<String, dynamic> ? RinEvent(type, json) : null;
    } on FormatException {
      return null;
    }
  }

  /// The JSON error of a failed stream request (the body is a byte stream).
  static Future<ApiError> _error(DioException e) async {
    final response = e.response;
    if (response == null) return const ApiError(code: ApiError.network);
    Object? body;
    final data = response.data;
    if (data is ResponseBody) {
      try {
        final text = await data.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .join();
        body = jsonDecode(text);
      } on Object {
        body = null;
      }
    }
    return ApiError.fromResponse(response.statusCode, body);
  }
}
