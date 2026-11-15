import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level security rules (doc 07 §4.3, doc 09 §5). They run as tests so
/// CI fails on any violation.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.endsWith('.g.dart'))
      .where((f) => !f.path.endsWith('.freezed.dart'))
      .toList();

  String normalised(File f) => f.path.replaceAll(r'\', '/');

  test('no raw TextField/TextFormField outside the shared NcTextField', () {
    final rawField = RegExp(r'\b(TextField|TextFormField)\s*\(');
    final offenders = [
      for (final file in dartFiles)
        if (!normalised(file)
                .endsWith('lib/shared/widgets/nc_text_field.dart') &&
            rawField.hasMatch(file.readAsStringSync()))
          normalised(file),
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Use NcTextField (requires an InputValidators validator + maxLength)',
    );
  });

  test('no print() in app code (use AppLogger, silent in release)', () {
    final printCall = RegExp(r'(^|[^\w.])print\s*\(', multiLine: true);
    final offenders = [
      for (final file in dartFiles)
        if (printCall.hasMatch(file.readAsStringSync())) normalised(file),
    ];
    expect(offenders, isEmpty);
  });

  test('debugPrint only inside AppLogger', () {
    final offenders = [
      for (final file in dartFiles)
        if (!normalised(file).endsWith('lib/core/utils/logger.dart') &&
            file.readAsStringSync().contains('debugPrint('))
          normalised(file),
    ];
    expect(offenders, isEmpty);
  });

  test('no colour literals outside the design tokens (doc 02 section 1)', () {
    final literal = RegExp(r'Color\(0x|\bColors\.[a-z]');
    final offenders = [
      for (final file in dartFiles)
        if (!normalised(file).endsWith('lib/core/theme/tokens.dart') &&
            !normalised(file).contains('/generated/') &&
            literal.hasMatch(file.readAsStringSync()))
          normalised(file),
    ];
    expect(offenders, isEmpty, reason: 'Use NcColors / context.nc');
  });

  test('no invisible or bidi control characters in lib/ or test/', () {
    bool banned(int c) =>
        (c >= 0x200B && c <= 0x200F) ||
        (c >= 0x202A && c <= 0x202E) ||
        (c >= 0x2066 && c <= 0x2069) ||
        c == 0xFEFF;
    final findings = <String>[];
    for (final dir in ['lib', 'test']) {
      for (final file in Directory(dir).listSync(recursive: true)) {
        final name = file.path.replaceAll(r'\', '/');
        if (file is! File || !RegExp(r'\.(dart|arb)$').hasMatch(name)) {
          continue;
        }
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (lines[i].runes.any(banned)) findings.add('$name:${i + 1}');
        }
      }
    }
    expect(findings, isEmpty);
  });

  test(
    'no WebView or HTML-rendering packages (user text is plain Text only)',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      const banned = [
        'webview_flutter',
        'flutter_inappwebview',
        'flutter_html',
        'flutter_widget_from_html',
        'flutter_markdown',
        'markdown_widget',
      ];
      for (final package in banned) {
        expect(pubspec, isNot(contains('$package:')), reason: package);
      }
    },
  );

  test('no secrets-looking values committed in env examples', () {
    final secretish = RegExp(
      r'(PRIVATE KEY|sk-ant-|AKIA[0-9A-Z]{16}|"type":\s*"service_account")',
    );
    for (final path in ['.env.example', 'env/test.env']) {
      expect(secretish.hasMatch(File(path).readAsStringSync()), isFalse);
    }
  });
}
