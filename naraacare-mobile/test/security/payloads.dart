import 'dart:convert';
import 'dart:io';

/// Shared script/markup payload list (doc 07 section 4.7), byte-identical to
/// naraacare-backend/tests/security/payloads/xss.txt.
const payloadListVersion = '1.0.0';

List<String> loadPayloads() {
  final lines = File('test/security/payloads/xss.txt').readAsLinesSync();
  return [
    for (final line in lines)
      if (line.startsWith('json:'))
        jsonDecode(line.substring(5)) as String
      else if (line.isNotEmpty && !line.startsWith('#'))
        line,
  ];
}
