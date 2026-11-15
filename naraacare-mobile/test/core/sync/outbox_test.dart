import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/sync/conflict_resolver.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/core/sync/sync_engine.dart';

const key = 'k8Jt0r4Pz2mYxV9aQ1sB6nW3eL7cU5hD0fG2iK4oR8s=';

/// Scripted server: answers each request with the next queued response.
class ScriptedApi implements HttpClientAdapter {
  final responses = <(int, Object)>[];
  final seen = <(String, String, Object?, Object?)>[];
  bool offline = false;

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
    seen.add((
      options.method,
      options.path,
      options.data,
      options.headers['If-Match'],
    ));
    final (status, body) = responses.removeAt(0);
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

void main() {
  late AppDatabase db;
  late ScriptedApi server;
  late Outbox outbox;
  late SyncEngine engine;

  Future<void> localEntry(String id) => db
      .into(db.localEntries)
      .insert(
        LocalEntriesCompanion.insert(
          clientEntryId: id,
          kind: 'hydration',
          localDate: '2026-10-31',
          payload: '{"volume_ml": 250}',
          state: 'pending',
          updatedAt: DateTime.utc(2026, 10, 31),
        ),
      );

  Future<LocalEntry> entry(String id) => (db.select(
    db.localEntries,
  )..where((t) => t.clientEntryId.equals(id))).getSingle();

  setUp(() {
    db = AppDatabase.memory(key);
    server = ScriptedApi();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test/'))
      ..httpClientAdapter = server;
    outbox = Outbox(db);
    engine = SyncEngine(
      outbox: outbox,
      api: ApiClient(dio),
      resolver: ConflictResolver(db),
    );
  });

  tearDown(() => db.close());

  Future<String> logWater() async {
    final id = await outbox.enqueue(
      resource: 'hydration_intake',
      method: 'POST',
      path: 'hydration/intakes',
      body: {'volume_ml': 250},
    );
    await localEntry(id);
    return id;
  }

  test('offline writes queue up and replay in order with their ids', () async {
    final first = await logWater();
    final second = await logWater();
    server.offline = true;
    final paused = await engine.flush();
    expect(paused.stoppedOn, 'NETWORK');
    expect(await outbox.count(), 2);
    expect((await outbox.pending()).first.attempts, 1);

    server
      ..offline = false
      ..responses.addAll([
        (201, {'id': 'srv-1', 'version': 1}),
        (201, {'id': 'srv-2', 'version': 1}),
      ]);
    final done = await engine.flush();
    expect(done.sent, 2);
    expect(await outbox.count(), 0);
    final bodies = server.seen.map((s) => s.$3! as Map).toList();
    expect(bodies.map((b) => b['client_entry_id']), [first, second]);
    expect((await entry(first)).state, 'synced');
    expect((await entry(first)).serverId, 'srv-1');
  });

  test('a replay answered 200 (duplicate) is treated as success', () async {
    final id = await logWater();
    server.responses.add((200, {'id': 'srv-1', 'version': 1}));
    expect((await engine.flush()).sent, 1);
    expect((await entry(id)).state, 'synced');
  });

  test('409 version conflict: the server copy wins and is flagged', () async {
    final id = await outbox.enqueue(
      resource: 'hydration_intake',
      method: 'PUT',
      path: 'hydration/intakes/srv-1',
      body: {'volume_ml': 300},
      ifMatchVersion: 1,
    );
    await localEntry(id);
    server.responses.add((
      409,
      {
        'error': {
          'code': 'VERSION_CONFLICT',
          'current': {'id': 'srv-1', 'version': 2, 'volume_ml': 200},
        },
      },
    ));
    final result = await engine.flush();
    expect(result.conflicts, 1);
    expect(server.seen.single.$4, '1'); // If-Match sent
    final local = await entry(id);
    expect(local.state, 'conflict');
    expect(local.version, 2);
    expect(jsonDecode(local.payload), containsPair('volume_ml', 200));
    expect(await outbox.count(), 0);
  });

  test(
    '403/422 rejections roll back locally and do not block the queue',
    () async {
      final rejected = await logWater();
      final accepted = await logWater();
      server.responses.addAll([
        (
          403,
          {
            'error': {'code': 'EDIT_WINDOW_CLOSED'},
          },
        ),
        (201, {'id': 'srv-2', 'version': 1}),
      ]);
      final result = await engine.flush();
      expect((result.rejected, result.sent), (1, 1));
      expect((await entry(rejected)).state, 'rejected');
      expect((await entry(rejected)).rejectionCode, 'EDIT_WINDOW_CLOSED');
      expect((await entry(accepted)).state, 'synced');
    },
  );

  test('server errors pause the queue and keep the order', () async {
    await logWater();
    await logWater();
    server.responses.add((
      503,
      {
        'error': {'code': 'SERVICE_UNAVAILABLE'},
      },
    ));
    final result = await engine.flush();
    expect(result.stoppedOn, 'SERVICE_UNAVAILABLE');
    expect(await outbox.count(), 2);
    expect(server.seen, hasLength(1));
  });

  test('concurrent flushes share one run', () async {
    await logWater();
    server.responses.add((201, {'id': 'srv-1', 'version': 1}));
    final results = await Future.wait([engine.flush(), engine.flush()]);
    expect(identical(results[0], results[1]), isTrue);
    expect(server.seen, hasLength(1));
  });

  test('coming back online triggers a flush', () async {
    await logWater();
    server.responses.add((201, {'id': 'srv-1', 'version': 1}));
    final online = StreamController<bool>();
    engine.watch(online.stream);
    online.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await outbox.count(), 0);
    await online.close();
    await engine.dispose();
  });
}
