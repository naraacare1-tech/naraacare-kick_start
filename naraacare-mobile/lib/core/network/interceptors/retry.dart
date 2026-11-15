import 'dart:async';

import 'package:dio/dio.dart';

/// Retries idempotent GETs on network errors and 502/503/504, with backoff
/// (300 ms, 900 ms). Writes are never retried here: the offline outbox owns
/// write retries, using `client_entry_id` for idempotency.
class RetryInterceptor extends Interceptor {
  new({
    required this.retry,
    this.delays = const [
      Duration(milliseconds: 300),
      Duration(milliseconds: 900),
    ],
  });

  final Future<Response<dynamic>> Function(RequestOptions options) retry;
  final List<Duration> delays;

  static const _retryStatuses = {502, 503, 504};

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (options.method != 'GET' || !_transient(err)) {
      handler.next(err);
      return;
    }
    // [retry] goes through a client without this interceptor, so the whole
    // backoff schedule runs here.
    var last = err;
    for (final delay in delays) {
      await Future<void>.delayed(delay);
      try {
        handler.resolve(await retry(options));
        return;
      } on DioException catch (e) {
        last = e;
        if (!_transient(e)) break;
      }
    }
    handler.next(last);
  }

  static bool _transient(DioException err) => switch (err.type) {
    DioExceptionType.connectionError ||
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout => true,
    DioExceptionType.badResponse => _retryStatuses.contains(
      err.response?.statusCode,
    ),
    _ => false,
  };
}
