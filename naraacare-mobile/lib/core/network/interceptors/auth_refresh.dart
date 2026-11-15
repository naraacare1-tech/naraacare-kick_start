import 'dart:async';

import 'package:dio/dio.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/utils/logger.dart';

/// Calls POST /auth/token/refresh; returns the new token pair as JSON, or
/// throws [ApiError]. Uses a client WITHOUT this interceptor.
typedef RefreshCall = Future<Map<String, dynamic>> Function(
  String refreshToken,
);

/// Adds the access token and renews it when the API answers 401
/// `TOKEN_EXPIRED` (doc 04 section 2.1).
///
/// Refreshes are single-flight: concurrent 401s wait for ONE refresh and then
/// retry with the new token. The API detects refresh-token reuse and revokes
/// the whole session (OQ-60, strict), so the app must never send the same
/// refresh token twice.
class AuthRefreshInterceptor extends QueuedInterceptor {
  new({required this.session, required this.refresh, required this.retry});

  final SessionStore session;
  final RefreshCall refresh;

  /// Re-sends a request after a refresh, through a client WITHOUT this
  /// interceptor (a queued interceptor that re-entered itself would wait for
  /// its own error handler forever). The new token is already set.
  final Future<Response<dynamic>> Function(RequestOptions options) retry;

  Future<bool>? _inFlight;

  static const _retried = 'nc_auth_retried';
  static const _sentWith = 'nc_auth_token';
  static const skipAuth = 'nc_skip_auth';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra[skipAuth] != true) {
      final tokens = await session.tokens();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
        options.extra[_sentWith] = tokens.accessToken;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final expired =
        err.response?.statusCode == 401 &&
        _code(err.response?.data) == ApiError.tokenExpired;
    if (!expired ||
        options.extra[skipAuth] == true ||
        options.extra[_retried] == true) {
      handler.next(err);
      return;
    }
    // Errors are handled one at a time (queued). If another request already
    // renewed the token after this one was sent, just retry with the new
    // token: refreshing again would waste the rotation (and, with strict
    // reuse detection, risk ending the session).
    final current = await session.tokens();
    final staleRequest =
        current != null && current.accessToken != options.extra[_sentWith];
    if (!staleRequest && !await refreshOnce()) {
      handler.next(err);
      return;
    }
    final tokens = await session.tokens();
    if (tokens == null) {
      handler.next(err);
      return;
    }
    try {
      options
        ..extra[_retried] = true
        ..headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      handler.resolve(await retry(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// One refresh for any number of concurrent callers.
  Future<bool> refreshOnce() => _inFlight ??= _refresh().whenComplete(() {
    _inFlight = null;
  });

  Future<bool> _refresh() async {
    final tokens = await session.tokens();
    if (tokens == null) return false;
    try {
      final pair = await refresh(tokens.refreshToken);
      await session.save(
        accessToken: pair['access_token'] as String,
        refreshToken: pair['refresh_token'] as String,
        accessExpiresInSeconds: pair['access_expires_in_s'] as int,
      );
      return true;
    } on ApiError catch (e) {
      if (e.isNetwork) return false; // keep the session; try again later
      log.info('session_refresh_refused', {'code': e.code});
      await session.clear();
      return false;
    }
  }

  static String? _code(Object? body) {
    if (body is Map && body['error'] is Map) {
      final code = (body['error'] as Map)['code'];
      return code is String ? code : null;
    }
    return null;
  }
}
