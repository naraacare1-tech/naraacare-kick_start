import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/core/security/secure_storage.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/core/theme/app_theme.dart';

Map<String, dynamic> tokenPairJson({bool onboardingRequired = false}) => {
  'access_token': 'access-new',
  'access_expires_in_s': 900,
  'refresh_token': 'refresh-new',
  'refresh_expires_in_s': 5184000,
  'token_type': 'Bearer',
  'onboarding_required': onboardingRequired,
};

Map<String, dynamic> tokenPair({bool onboardingRequired = false}) =>
    tokenPairJson(onboardingRequired: onboardingRequired);

/// A scripted API for widget tests (no network). Answers from a per-path
/// queue ([on]) first, then from the FIFO [responses], else 404.
class FakeServer implements HttpClientAdapter {
  final responses = <(int, Object)>[];
  final routes = <String, List<(int, Object?)>>{};
  final paths = <String>[];

  /// Every request as (method, path, body), in order.
  final requests = <(String, String, Object?)>[];
  bool offline = false;

  /// Queues a response for [path] (e.g. `auth/signup`); the last one for a
  /// path is repeated.
  void on(String path, int status, [Object? body]) =>
      (routes[path] ??= []).add((status, body));

  /// Bodies sent to [path].
  List<Object?> bodiesFor(String path) => [
    for (final (_, p, body) in requests)
      if (p == path) body,
  ];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (offline) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    }
    paths.add(options.path);
    requests.add((options.method, options.path, options.data));
    final queue = routes[options.path];
    final (status, body) = queue != null && queue.isNotEmpty
        ? (queue.length > 1 ? queue.removeAt(0) : queue.first)
        : responses.isEmpty
        ? (
            404,
            <String, Object>{
              'error': {'code': 'NOT_FOUND'},
            },
          )
        : responses.removeAt(0);
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// In-memory storage, session, fake server and API client.
class Harness {
  final keys = MemoryKeyValueStore();
  late final storage = SecureStorage(keys);
  late final session = SessionStore(storage);
  final server = FakeServer();
  late final api = ApiClient(
    Dio(BaseOptions(baseUrl: 'https://api.test/'))..httpClientAdapter = server,
  );

  void respond(int status, Object body) => server.responses.add((status, body));

  Future<void> signIn({bool onboardingComplete = true}) async {
    await session.save(
      accessToken: 'access-old',
      refreshToken: 'refresh-old',
      accessExpiresInSeconds: 900,
    );
    await storage.writeFlag(
      'app.onboarding_complete',
      value: onboardingComplete,
    );
  }

  AuthController authController() =>
      AuthController(storage: storage, session: session, api: api);

  /// The app's screens read providers: the scope points them at this
  /// harness's storage and fake API.
  Widget wrapRouter(GoRouter router) => ProviderScope(
    overrides: [
      keyValueStoreProvider.overrideWithValue(keys),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: localizations,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}

const localizations = <LocalizationsDelegate<Object>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Wraps a widget with the app theme and localisation.
Widget themed(Widget child, {TargetPlatform? platform}) => MaterialApp(
  theme: AppTheme.light(platform: platform),
  localizationsDelegates: localizations,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
