import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'payloads.dart';

void main() {
  test('payload list has the expected version', () {
    final header = File('test/security/payloads/xss.txt')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('# payload-list-version:'));
    expect(header.split(':').last.trim(), payloadListVersion);
  });

  test('payload list loads, is large and unique', () {
    final payloads = loadPayloads();
    expect(payloads.length, greaterThanOrEqualTo(300));
    expect(payloads.toSet().length, payloads.length);
    expect(payloads, contains('abc\u0000def'));
  });
}
