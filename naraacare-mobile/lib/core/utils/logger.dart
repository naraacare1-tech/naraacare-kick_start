import 'package:flutter/foundation.dart';

/// The app's only logging entry point (doc 07 SEC-5.3): a no-op in release
/// builds, and never given user input, tokens or health values. Messages are
/// fixed event names with codes, e.g. `log.info('sync_flush', {'sent': 3})`.
class AppLogger {
  const new({this.enabled = !kReleaseMode, this.sink});

  final bool enabled;

  /// Where lines go (tests); `debugPrint` when null.
  final void Function(String line)? sink;

  void info(String event, [Map<String, Object?> fields = const {}]) =>
      _write('INFO', event, fields);

  void warning(String event, [Map<String, Object?> fields = const {}]) =>
      _write('WARN', event, fields);

  void _write(String level, String event, Map<String, Object?> fields) {
    if (!enabled) return;
    final extra = fields.isEmpty ? '' : ' $fields';
    final line = '[$level] $event$extra';
    final write = sink;
    if (write != null) {
      write(line);
    } else {
      debugPrint(line);
    }
  }
}

const log = AppLogger();
