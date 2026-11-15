import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:naraacare/core/config/app_config.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/interceptors/auth_refresh.dart';
import 'package:naraacare/core/network/interceptors/request_id.dart';
import 'package:naraacare/core/network/interceptors/retry.dart';
import 'package:naraacare/core/network/pinning.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/security/secure_storage.dart';

/// JSON over HTTPS to the API (doc 04). Every failure leaves as [ApiError];
/// callers never see dio types. Bodies are never logged.
class ApiClient {
  new(this.dio);

  /// Production wiring: base URL and pins from the build config, the session
  /// interceptors, and an installation-bound refresh call.
  factory create({
    required AppConfig config,
    required SessionStore session,
    required SecureStorage storage,
    HttpClient Function()? httpClientFactory,
  }) {
    Dio build() {
      final dio = Dio(
        BaseOptions(
          baseUrl: '${config.apiBaseUrl}/',
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 20),
          contentType: Headers.jsonContentType,
        ),
      );
      return dio
        ..httpClientAdapter = IOHttpClientAdapter(
          createHttpClient: httpClientFactory,
          validateCertificate: (certificate, host, port) =>
              CertificatePinning.isPinned(certificate, config.certPins),
        );
    }

    // A bare client for the refresh call itself and for retries after a
    // refresh (no auth interceptor: a failing call cannot recurse).
    final refreshDio = build()..interceptors.add(RequestIdInterceptor());
    final retryDio = build()..interceptors.add(RequestIdInterceptor());
    final dio = build();
    final client = ApiClient(dio);
    dio.interceptors.addAll([
      RequestIdInterceptor(),
      AuthRefreshInterceptor(
        session: session,
        refresh: (refreshToken) async {
          final response = await ApiClient(refreshDio).post(
            'auth/token/refresh',
            body: {
              'refresh_token': refreshToken,
              'installation_id': await storage.installationId(),
            },
          );
          return response! as Map<String, dynamic>;
        },
        retry: retryDio.fetch<dynamic>,
      ),
      RetryInterceptor(retry: retryDio.fetch<dynamic>),
    ]);
    return client;
  }

  final Dio dio;

  Future<Object?> get(String path, {Map<String, Object?>? query}) =>
      _send(() => dio.get<Object?>(path, queryParameters: query));

  Future<Object?> post(String path, {Object? body, Options? options}) =>
      _send(() => dio.post<Object?>(path, data: body, options: options));

  Future<Object?> put(String path, {Object? body, Options? options}) =>
      _send(() => dio.put<Object?>(path, data: body, options: options));

  Future<Object?> patch(String path, {Object? body, Options? options}) =>
      _send(() => dio.patch<Object?>(path, data: body, options: options));

  Future<Object?> delete(String path, {Options? options}) =>
      _send(() => dio.delete<Object?>(path, options: options));

  /// Requests that must not carry the access token (sign-in, sign-up).
  static Options get public =>
      Options(extra: {AuthRefreshInterceptor.skipAuth: true});

  Future<Object?> _send(Future<Response<Object?>> Function() call) async {
    try {
      return (await call()).data;
    } on DioException catch (e) {
      throw toApiError(e);
    }
  }

  static ApiError toApiError(DioException e) {
    if (e.error is ApiError) return e.error! as ApiError;
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const ApiError(code: ApiError.timeout);
      case DioExceptionType.badCertificate:
        return const ApiError(code: ApiError.certificate);
      case DioExceptionType.connectionError:
        return e.error is HandshakeException
            ? const ApiError(code: ApiError.certificate)
            : const ApiError(code: ApiError.network);
      case DioExceptionType.badResponse:
        final response = e.response;
        return ApiError.fromResponse(
          response?.statusCode,
          response?.data,
          retryAfterHeader: int.tryParse(
            response?.headers.value('retry-after') ?? '',
          ),
        );
      case DioExceptionType.cancel:
      case DioExceptionType.unknown:
        return e.error is SocketException
            ? const ApiError(code: ApiError.network)
            : const ApiError(code: ApiError.unknown);
    }
  }
}
