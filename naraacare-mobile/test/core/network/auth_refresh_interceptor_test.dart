import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/network/interceptors/auth_refresh.dart';
import 'package:naraacare/core/network/interceptors/request_id.dart';
import 'package:naraacare/core/network/interceptors/retry.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/security/secure_storage.dart';

/// A fake API: 401 TOKEN_EXPIRED for the old access token, 200 for the new.
class FakeApi implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final requestIds = <Object?>[];
  String validToken = 'access-2';
  int failuresBeforeSuccess = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    requestIds.add(options.headers['X-Request-ID']);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      return _json(503, {
        'error': {'code': 'SERVICE_UNAVAILABLE'},
      });
    }
    final auth = options.headers['Authorization'];
    if (auth != 'Bearer $validToken') {
      return _json(401, {
        'error': {'code': 'TOKEN_EXPIRED', 'request_id': 'r'},
      });
    }
    return _json(200, {'path': options.path});
  }

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}

Future<(ApiClient, FakeApi, SessionStore, List<String>)> build({
  Future<Map<String, dynamic>> Function(String)? refresh,
}) async {
  final api = FakeApi();
  final session = SessionStore(SecureStorage(MemoryKeyValueStore()));
  await session.save(
    accessToken: 'access-1',
    refreshToken: 'refresh-1',
    accessExpiresInSeconds: 900,
  );
  final refreshedWith = <String>[];
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test/'))
    ..httpClientAdapter = api;
  // Like production: retries go through a client without the auth and
  // retry interceptors (see ApiClient.create).
  final retryDio = Dio(BaseOptions(baseUrl: 'https://api.test/'))
    ..httpClientAdapter = api
    ..interceptors.add(RequestIdInterceptor());
  dio.interceptors.addAll([
    RequestIdInterceptor(),
    AuthRefreshInterceptor(
      session: session,
      refresh:
          refresh ??
          (token) async {
            refreshedWith.add(token);
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return {
              'access_token': 'access-2',
              'refresh_token': 'refresh-2',
              'access_expires_in_s': 900,
            };
          },
      retry: retryDio.fetch<dynamic>,
    ),
    RetryInterceptor(
      retry: retryDio.fetch<dynamic>,
      delays: const [Duration.zero, Duration.zero],
    ),
  ]);
  return (ApiClient(dio), api, session, refreshedWith);
}

void main() {
  test('concurrent 401s trigger exactly one refresh, then all retry', () async {
    final (client, api, session, refreshedWith) = await build();
    final results = await Future.wait([
      for (var i = 0; i < 5; i++) client.get('me/$i'),
    ]);
    expect(results, hasLength(5));
    expect(refreshedWith, ['refresh-1']); // one refresh, the stored token
    expect((await session.tokens())!.refreshToken, 'refresh-2');
    // A fresh request id for every attempt, retries included.
    expect(api.requestIds.toSet(), hasLength(api.requests.length));
  });

  test('a refused refresh ends the session', () async {
    final (client, _, session, _) = await build(
      refresh: (_) async =>
          throw const ApiError(code: ApiError.unauthenticated, status: 401),
    );
    final ended = expectLater(session.sessionEnded, emits(null));
    await expectLater(
      client.get('me'),
      throwsA(isA<ApiError>().having((e) => e.code, 'code', 'TOKEN_EXPIRED')),
    );
    await ended;
    expect(await session.tokens(), isNull);
  });

  test('offline during refresh keeps the session', () async {
    final (client, _, session, _) = await build(
      refresh: (_) async => throw const ApiError(code: ApiError.network),
    );
    await expectLater(client.get('me'), throwsA(isA<ApiError>()));
    expect((await session.tokens())!.refreshToken, 'refresh-1');
  });

  test('public requests carry no access token', () async {
    final (client, api, _, _) = await build();
    api.validToken = 'nothing';
    await expectLater(
      client.post('auth/login', body: {}, options: ApiClient.public),
      throwsA(isA<ApiError>()),
    );
    expect(api.requests.first.headers.containsKey('Authorization'), isFalse);
  });

  test('GETs are retried on 503, writes are not', () async {
    final (client, api, _, _) = await build();
    api
      ..validToken = 'access-1'
      ..failuresBeforeSuccess = 2;
    expect(await client.get('reference/bootstrap'), isNotNull);
    expect(api.requests, hasLength(3));

    api
      ..requests.clear()
      ..failuresBeforeSuccess = 1;
    await expectLater(
      client.post('hydration/intakes', body: {}),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 503)),
    );
    expect(api.requests, hasLength(1));
  });

  test('error envelopes become ApiError with safe details only', () {
    final error = ApiError.fromResponse(409, const {
      'error': {
        'code': 'LINK_REQUIRED',
        'link_token': 'abc.def',
        'fields': ['email'],
        'retry_after_s': 30,
        'unexpected': '<script>',
      },
    });
    expect(error.code, 'LINK_REQUIRED');
    expect(error.details, {'link_token': 'abc.def'});
    expect(error.fields, ['email']);
    expect(error.retryAfterSeconds, 30);
    expect(ApiError.fromResponse(502, '<html>').code, ApiError.internalError);
  });
}
