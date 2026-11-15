import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:naraacare/core/errors/api_error.dart';
import 'package:naraacare/core/network/api_client.dart';
import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/sync/conflict_resolver.dart';
import 'package:naraacare/core/sync/outbox.dart';
import 'package:naraacare/core/utils/logger.dart';

/// Result of one flush.
class FlushResult {
  const new({
    this.sent = 0,
    this.conflicts = 0,
    this.rejected = 0,
    this.stoppedOn,
  });

  final int sent;
  final int conflicts;
  final int rejected;

  /// Why the flush stopped early (offline, server busy, signed out).
  final String? stoppedOn;
}

/// Sends the outbox to the API in order (doc 03 section 3.1).
///
/// * Runs when the app comes online or to the foreground; one flush at a
///   time (a second request while running waits for the same result).
/// * Transient trouble (offline, timeouts, 5xx, 429, 401) STOPS the flush and
///   keeps the item, so order is preserved; it runs again on the next trigger.
/// * 2xx, 409 and 403/404/422 settle the item (see [ConflictResolver]).
/// * After each flush, [pull] fetches other devices' changes
///   (`GET /sync/changes`, S14); a failed pull never fails the flush.
/// * A flush stopped by the server (5xx, 429, timeouts) is retried with
///   exponential backoff (5 s, 10 s, 20 s ... at most 5 min); offline waits
///   for the reconnect trigger instead. The app also flushes on resume.
class SyncEngine {
  new({
    required this.outbox,
    required this.api,
    required this.resolver,
    this.pull,
  });

  final Outbox outbox;
  final ApiClient api;
  final ConflictResolver resolver;
  final Future<void> Function()? pull;

  Future<FlushResult>? _running;
  StreamSubscription<bool>? _onlineSub;
  Timer? _retry;
  int _failures = 0;

  static const _maxBackoff = Duration(minutes: 5);

  void _scheduleRetry() {
    _retry?.cancel();
    final seconds = min(_maxBackoff.inSeconds, 5 * pow(2, _failures).toInt());
    _failures = min(_failures + 1, 10);
    _retry = Timer(Duration(seconds: seconds), () => unawaited(flush()));
  }

  /// Flush whenever connectivity comes back.
  void watch(Stream<bool> onlineChanges) {
    _onlineSub ??= onlineChanges.where((online) => online).listen((_) {
      unawaited(flush());
    });
  }

  Future<FlushResult> flush() => _running ??= _flush().whenComplete(() {
    _running = null;
  });

  Future<FlushResult> _flush() async {
    var sent = 0;
    var conflicts = 0;
    var rejected = 0;
    for (final item in await outbox.pending()) {
      try {
        final response = await _send(item);
        await resolver.accepted(item.clientEntryId, response);
        await outbox.remove(item);
        sent++;
      } on ApiError catch (e) {
        if (_transient(e)) {
          await outbox.recordFailure(item, e.code);
          log.info('sync_flush_paused', {'code': e.code, 'sent': sent});
          if (!e.isNetwork) _scheduleRetry();
          return FlushResult(
            sent: sent,
            conflicts: conflicts,
            rejected: rejected,
            stoppedOn: e.code,
          );
        }
        if (e.status == 409) {
          await resolver.serverWins(item.clientEntryId, e.serverCopy);
          conflicts++;
        } else {
          await resolver.rejected(item.clientEntryId, e.code);
          rejected++;
        }
        await outbox.remove(item);
      }
    }
    _failures = 0;
    _retry?.cancel();
    if (pull != null) {
      try {
        await pull!();
      } on Object catch (e) {
        log.info('sync_pull_failed', {'error': e.runtimeType.toString()});
      }
    }
    log.info('sync_flush_done', {
      'sent': sent,
      'conflicts': conflicts,
      'rejected': rejected,
    });
    return FlushResult(sent: sent, conflicts: conflicts, rejected: rejected);
  }

  Future<Object?> _send(OutboxItem item) {
    final body = item.body == null ? null : jsonDecode(item.body!);
    final options = Options(
      headers: {
        if (item.ifMatchVersion != null) 'If-Match': '${item.ifMatchVersion}',
      },
    );
    return switch (item.method) {
      'POST' => api.post(item.path, body: body, options: options),
      'PUT' => api.put(item.path, body: body, options: options),
      'PATCH' => api.patch(item.path, body: body, options: options),
      'DELETE' => api.delete(item.path, options: options),
      _ => throw ArgumentError.value(item.method, 'method'),
    };
  }

  static bool _transient(ApiError e) {
    final status = e.status;
    return e.isNetwork ||
        e.code == ApiError.certificate ||
        status == null ||
        status == 401 ||
        status == 429 ||
        status >= 500;
  }

  Future<void> dispose() async {
    _retry?.cancel();
    await _onlineSub?.cancel();
  }
}
