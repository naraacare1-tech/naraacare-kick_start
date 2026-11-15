import 'package:flutter/foundation.dart';

/// The uniform error envelope of the API (doc 04 section 1.1), parsed. Only
/// catalogued codes and field names travel; never input values.
@immutable
class ApiError implements Exception {
  const new({
    required this.code,
    this.status,
    this.fields = const [],
    this.requestId,
    this.retryAfterSeconds,
    this.attemptsLeft,
    this.limit,
    this.details = const {},
    this.serverCopy,
  });

  /// From a decoded response body; unknown shapes become [unknown].
  factory fromResponse(int? status, Object? body, {int? retryAfterHeader}) {
    final error = body is Map<String, dynamic> ? body['error'] : null;
    if (error is! Map<String, dynamic> || error['code'] is! String) {
      return ApiError(
        code: status != null && status >= 500 ? internalError : unknown,
        status: status,
      );
    }
    int? asInt(Object? v) => v is int ? v : int.tryParse('$v');
    final fields = error['fields'];
    return ApiError(
      code: error['code'] as String,
      status: status,
      fields: fields is List ? fields.whereType<String>().toList() : const [],
      requestId: error['request_id'] as String?,
      retryAfterSeconds: asInt(error['retry_after_s']) ?? retryAfterHeader,
      attemptsLeft: asInt(error['attempts_left']),
      limit: asInt(error['limit']),
      details: {
        for (final key in const ['challenge_id', 'link_token', 'feature'])
          if (error[key] is String) key: error[key] as String,
      },
      serverCopy: error['current'] is Map<String, dynamic>
          ? error['current'] as Map<String, dynamic>
          : null,
    );
  }

  // Codes produced by the app itself (no server response).
  static const network = 'NETWORK';
  static const timeout = 'TIMEOUT';
  static const unknown = 'UNKNOWN';
  static const certificate = 'CERTIFICATE';
  // Server codes the app reacts to specifically.
  static const internalError = 'INTERNAL_ERROR';
  static const tokenExpired = 'TOKEN_EXPIRED';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const versionConflict = 'VERSION_CONFLICT';
  static const rateLimited = 'RATE_LIMITED';
  static const upgradeRequired = 'UPGRADE_REQUIRED';

  final String code;
  final int? status;
  final List<String> fields;
  final String? requestId;
  final int? retryAfterSeconds;
  final int? attemptsLeft;

  /// DAILY_LIMIT_REACHED: the user's daily limit (4 STANDARD, 8 STAR).
  final int? limit;

  /// Safe extras the API attaches to some errors (challenge id, link token).
  final Map<String, String> details;

  /// 409 VERSION_CONFLICT: the server's current copy of the resource.
  final Map<String, dynamic>? serverCopy;

  bool get isNetwork => code == network || code == timeout;

  @override
  String toString() => 'ApiError($code, status: $status)';
}
