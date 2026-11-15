import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Sends a fresh UUIDv7 `X-Request-ID` per request (doc 04 section 1); the API
/// echoes it in errors, so support can correlate a report with server logs.
class RequestIdInterceptor extends Interceptor {
  static const header = 'X-Request-ID';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers[header] = const Uuid().v7();
    handler.next(options);
  }
}
