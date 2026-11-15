import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Canonical reject patterns R1-R9 (doc 07 section 4.2), mirroring
/// naraacare-backend app/core/security/validators.py. Input that matches is
/// REJECTED, never stripped. This layer is for user experience; the API is the
/// security boundary and applies the same rules again.
///
/// Character classes are built from code points so this source file never
/// contains invisible characters (a test scans lib/ for them).
abstract final class RejectPatterns {
  static final String _control = String.fromCharCodes([
    for (var c = 0x00; c < 0x09; c++) c,
    0x0B,
    0x0C,
    for (var c = 0x0E; c < 0x20; c++) c,
    0x7F,
  ]);
  static final String _invisible = String.fromCharCodes([
    for (var c = 0x200B; c < 0x2010; c++) c, // zero-width, LRM, RLM
    for (var c = 0x202A; c < 0x202F; c++) c, // bidi embeddings, overrides
    for (var c = 0x2066; c < 0x206A; c++) c, // bidi isolates
    0xFEFF, // BOM / zero-width no-break space
  ]);
  static const int zwj = 0x200D;
  static const int _vs16 = 0xFE0F;

  static String _cls(String chars) =>
      '[${chars.runes.map((r) => '\\u{${r.toRadixString(16)}}').join()}]';

  static final _r5 = RegExp(_cls(_control + _invisible), unicode: true);
  static final _r5SingleLine = RegExp(
    _cls('$_control$_invisible\t\n\r'),
    unicode: true,
  );
  static final _r5MultiLine = RegExp(
    _cls('$_control$_invisible\t'),
    unicode: true,
  );
  static final _r6 = RegExp('&#x?[0-9a-f]+;?|&[a-z]+;', caseSensitive: false);
  static final _r7 = RegExp('%[0-9a-f]{2}', caseSensitive: false);
  static final _r8 = RegExp(
    r'\\u[0-9a-f]{4}|\\x[0-9a-f]{2}',
    caseSensitive: false,
  );
  static final _r3 = [
    RegExp(r'(javascript|vbscript|livescript)\s*:', caseSensitive: false),
    RegExp(r'data\s*:\s*[a-z]+/[a-z0-9.+-]+', caseSensitive: false),
  ];
  static final List<RegExp> _inspection = [
    RegExp('[<>]'), // R1 tags
    RegExp(r'(^|[^a-z])on[a-z]+\s*=', caseSensitive: false), // R2 handlers
    ..._r3,
    RegExp(r'\{\{|\}\}|\$\{|<%|%>|#\{'), // R4 templates
    RegExp(r'expression\s*\(|url\s*\(|@import', caseSensitive: false), // R9
  ];
  static final _whitespace = RegExp(
    '[\\s${_escape(_control)}]+',
    unicode: true,
  );
  static final RegExp _zwjInEmoji = RegExp(
    '(?<=[\\p{Extended_Pictographic}\\p{Emoji_Modifier}\\u{${_vs16.toRadixString(16)}}])'
    '\\u{${zwj.toRadixString(16)}}(?=\\p{Extended_Pictographic})',
    unicode: true,
  );
  static const _decodeRounds = 3;
  static const _replacement = 0xFFFD;

  static String _escape(String chars) =>
      chars.runes.map((r) => '\\u{${r.toRadixString(16)}}').join();

  /// Unicode NFKC, the same normalisation as the API (folds full-width
  /// `＜` to `<`, compatibility digits, ligatures).
  static String nfkc(String value) => unorm.nfkc(value);

  /// True when [raw] matches R1-R9 in any inspected form.
  static bool containsUnsafeContent(
    String raw, {
    bool multiline = false,
    bool allowEmojiZwj = false,
  }) {
    final candidate = allowEmojiZwj ? raw.replaceAll(_zwjInEmoji, '') : raw;
    final r5 = multiline ? _r5MultiLine : _r5SingleLine;
    if (r5.hasMatch(candidate)) return true;
    final normalised = nfkc(raw);
    for (final form in [raw, normalised]) {
      if (_r6.hasMatch(form) || _r7.hasMatch(form) || _r8.hasMatch(form)) {
        return true;
      }
    }
    for (final form in _decodedForms(normalised)) {
      if (_inspection.any((p) => p.hasMatch(form))) return true;
      // R3b: schemes split by whitespace or control characters.
      final stripped = form.replaceAll(_whitespace, '');
      if (_r3.any((p) => p.hasMatch(stripped))) return true;
      if (!identical(form, normalised) && _r5.hasMatch(form)) return true;
    }
    return false;
  }

  /// [value] plus up to 3 rounds of URL- and HTML-entity decoding.
  static List<String> _decodedForms(String value) {
    final forms = [value];
    var current = value;
    for (var i = 0; i < _decodeRounds; i++) {
      final decoded = _unescapeHtml(_percentDecode(current));
      if (decoded == current) break;
      forms.add(decoded);
      current = decoded;
    }
    return forms;
  }

  static final _percent = RegExp('%([0-9a-fA-F]{2})');

  /// Like Python's urllib.parse.unquote for inspection: %XX sequences are
  /// decoded as UTF-8 where valid, otherwise kept as Latin-1 code points.
  static String _percentDecode(String value) {
    if (!value.contains('%')) return value;
    return value.replaceAllMapped(
      _percent,
      (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
    );
  }

  static final _entity = RegExp(
    '&(#[0-9]+|#[xX][0-9a-fA-F]+|lt|gt|amp|quot|apos|LT|GT|AMP|QUOT);?',
  );
  static const _named = {
    'lt': '<',
    'gt': '>',
    'amp': '&',
    'quot': '"',
    'apos': "'",
    'LT': '<',
    'GT': '>',
    'AMP': '&',
    'QUOT': '"',
  };

  /// Decodes numeric entities and the named ones that can build markup,
  /// including the legacy forms without a semicolon that browsers (and
  /// Python's html.unescape) accept, such as `&lt`.
  static String _unescapeHtml(String value) {
    if (!value.contains('&')) return value;
    return value.replaceAllMapped(_entity, (m) {
      final body = m[1]!;
      if (body.startsWith('#')) {
        final hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
        final code = int.tryParse(
          hex ? body.substring(2) : body.substring(1),
          radix: hex ? 16 : 10,
        );
        if (code == null || code > 0x10FFFF || code == 0) {
          return String.fromCharCode(_replacement);
        }
        return String.fromCharCode(code);
      }
      return _named[body] ?? m[0]!;
    });
  }
}
