import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/network/connectivity.dart';
import 'package:naraacare/core/network/session_store.dart';
import 'package:naraacare/core/routing/app_router.dart';
import 'package:naraacare/core/security/biometric_gate.dart';
import 'package:naraacare/core/security/root_check.dart';
import 'package:naraacare/core/security/secure_storage.dart';
import 'package:naraacare/core/session/auth_controller.dart';
import 'package:naraacare/core/session/local_wipe.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/sync/conflict_resolver.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/core/sync/sync_engine.dart';
import 'package:naraacare/core/sync/sync_pull.dart';
import 'package:naraacare/core/utils/logger.dart';
import 'package:naraacare/features/notifications/data/local_reminders.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App-wide dependencies (Riverpod). Tests override the platform-facing ones
/// (key/value store, connectivity, root check, authenticator, database).

final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => const PlatformKeyValueStore(),
);

final secureStorageProvider = Provider<SecureStorage>(
  (ref) => SecureStorage(ref.watch(keyValueStoreProvider)),
);

final sessionStoreProvider = Provider<SessionStore>((ref) {
  final store = SessionStore(ref.watch(secureStorageProvider));
  ref.onDispose(store.dispose);
  return store;
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient.create(
    config: ref.watch(appConfigProvider),
    session: ref.watch(sessionStoreProvider),
    storage: ref.watch(secureStorageProvider),
  ),
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final storage = ref.watch(secureStorageProvider);
  final db = AppDatabase.lazy(() async {
    final dir = await getApplicationSupportDirectory();
    final key = await storage.databaseKey();
    return (File(p.join(dir.path, 'naraacare.db')), key);
  });
  ref.onDispose(db.close);
  return db;
});

final connectivityProvider = Provider<ConnectivityMonitor>(
  (ref) => PlatformConnectivity(),
);

final onlineProvider = StreamProvider<bool>((ref) async* {
  final monitor = ref.watch(connectivityProvider);
  yield await monitor.isOnline();
  yield* monitor.onlineChanges;
});

final outboxProvider = Provider<Outbox>(
  (ref) => Outbox(ref.watch(databaseProvider)),
);

/// Bumped when a sync pull brought changes from another device; the main
/// status providers watch it and reload.
class RemoteChanges extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final remoteChangesProvider = NotifierProvider<RemoteChanges, int>(
  RemoteChanges.new,
);

/// Local entries the server overwrote ("changed on another device").
final syncConflictCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.localEntries)..where((t) => t.state.equals('conflict')))
      .watch()
      .map((rows) => rows.length);
});

/// Marks the conflicts as seen (the banner's Dismiss).
Future<void> acknowledgeSyncConflicts(AppDatabase db) =>
    (db.update(db.localEntries)..where((t) => t.state.equals('conflict')))
        .write(const LocalEntriesCompanion(state: Value('synced')));

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final puller = SyncPuller(
    ref.watch(databaseProvider),
    ref.watch(apiClientProvider),
  );
  final engine = SyncEngine(
    outbox: ref.watch(outboxProvider),
    api: ref.watch(apiClientProvider),
    resolver: ConflictResolver(ref.watch(databaseProvider)),
    pull: () async {
      final result = await puller.pull();
      if (result.changed > 0) ref.read(remoteChangesProvider.notifier).bump();
    },
  )..watch(ref.watch(connectivityProvider).onlineChanges);
  ref.onDispose(engine.dispose);
  return engine;
});

final rootCheckProvider = Provider<RootCheck>(
  (ref) => const PlatformRootCheck(),
);

final deviceCompromisedProvider = FutureProvider<bool>(
  (ref) => ref.watch(rootCheckProvider).isCompromised(),
);

final authenticatorProvider = Provider<Authenticator>(
  (ref) => PlatformAuthenticator(),
);

/// The user's "biometric lock" setting (PUT /me/settings, off by default).
/// Session 07 sets it from GET /me.
class BiometricLockSetting extends Notifier<bool> {
  @override
  bool build() => false;

  bool get enabled => state;

  set enabled(bool value) => state = value;
}

final biometricLockEnabledProvider =
    NotifierProvider<BiometricLockSetting, bool>(BiometricLockSetting.new);

/// The router listens to the controller itself (a ChangeNotifier).
final authControllerProvider = Provider<AuthController>((ref) {
  final controller = AuthController(
    storage: ref.watch(secureStorageProvider),
    session: ref.watch(sessionStoreProvider),
    api: ref.watch(apiClientProvider),
    wipeLocalData: () async {
      // Nothing of the previous user keeps ringing after sign-out. Each step
      // runs even if the other fails: a reminders error must never leave the
      // previous user's health data on the phone.
      try {
        await ref.read(localRemindersProvider).clear();
      } on Object catch (e) {
        log.warning('local_reminders_clear_failed', {
          'type': e.runtimeType.toString(),
        });
      }
      await wipeLocalUserData(ref.read(databaseProvider));
    },
    onSignedOut: ref.read(restartAppProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(ref.watch(authControllerProvider));
  ref.onDispose(router.dispose);
  return router;
});
