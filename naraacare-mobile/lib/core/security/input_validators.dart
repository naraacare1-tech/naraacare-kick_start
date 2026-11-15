import 'package:naraacare/core/security/reject_patterns.dart';

/// Why a value was refused. Shown through localised messages that never
/// repeat the input (doc 07 section 4.3).
enum ValidationError {
  required,
  unsafe,
  format,
  tooShort,
  tooLong,
  mismatch,
  weakPassword,
  outOfRange,
}

typedef Validator = ValidationError? Function(String value);

/// Layer 1 of input validation (doc 07 section 4.3): the only validator module
/// of the app. Rules mirror the backend Safe* types (doc 04 section 1.2); the
/// API re-validates everything, so this layer exists for fast, friendly
/// feedback. Pipeline: reject patterns R1-R9 -> NFKC (+ trim) -> length (in
/// code points, like the API) -> per-type allow-list.
abstract final class InputValidators {
  static const _apostrophe = '\u{2019}';
  static const String _shortTextChars =
      r"\p{L}\p{M}\p{N} .,'\-()&/+%" + _apostrophe;
  static const String _textChars = _shortTextChars + r'!?:;"#@\n\r';
  static const _emojiChars =
      r'\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Regional_Indicator}'
      r'\u{200D}\u{FE0F}';

  static final _name = RegExp(
    r"^[\p{L}\p{M} .'\-" + _apostrophe + r']+$',
    unicode: true,
  );
  static final _hasLetter = RegExp(r'\p{L}', unicode: true);
  static final _username = RegExp(r'^[a-z0-9](?:[a-z0-9._]{1,28})[a-z0-9]$');
  static final _usernamePrefix = RegExp(r'^[a-z0-9._]+$');
  static final _usernameRepeat = RegExp('[._]{2}');
  static final _email = RegExp(
    '^[a-z0-9._+-]+@[a-z0-9](?:[a-z0-9-]*[a-z0-9])?'
    r'(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+$',
  );
  static final _otp = RegExp(r'^[0-9]{6}$');
  static final _shortText = RegExp('^[$_shortTextChars]+\$', unicode: true);
  static final _text = RegExp('^[$_textChars]+\$', unicode: true);
  static final _chat = RegExp('^[$_textChars$_emojiChars]+\$', unicode: true);
  static final _search = RegExp(r"^[\p{L}\p{M}\p{N} .'\-&@_]+$", unicode: true);
  static final _digits = RegExp(r'^[0-9]+$');
  static final _upper = RegExp(r'\p{Lu}', unicode: true);
  static final _digit = RegExp(r'\p{Nd}', unicode: true);

  // ------------------------------------------------------------------ core
  /// The value the app sends: NFKC-normalised and, for single-line fields,
  /// trimmed (the API stores the same form).
  static String normalise(String value, {bool trim = true}) {
    final n = RejectPatterns.nfkc(value);
    return trim ? n.trim() : n;
  }

  static ValidationError? _check(
    String raw, {
    required int max,
    required RegExp allow,
    int min = 1,
    bool multiline = false,
    bool allowEmojiZwj = false,
    String Function(String)? transform,
  }) {
    if (raw.trim().isEmpty) return ValidationError.required;
    if (RejectPatterns.containsUnsafeContent(
      raw,
      multiline: multiline,
      allowEmojiZwj: allowEmojiZwj,
    )) {
      return ValidationError.unsafe;
    }
    var value = normalise(raw);
    if (transform != null) value = transform(value);
    final length = value.runes.length;
    if (length < min) return ValidationError.tooShort;
    if (length > max) return ValidationError.tooLong;
    if (!allow.hasMatch(value)) return ValidationError.format;
    return null;
  }

  // ------------------------------------------------------------------ types
  /// Person name (SafeName, 100): letters and marks of any script, space,
  /// `. ' -`; must contain a letter.
  static ValidationError? name(String value) {
    final error = _check(value, max: 100, allow: _name);
    if (error != null) return error;
    return _hasLetter.hasMatch(value) ? null : ValidationError.format;
  }

  /// Username (SafeUsername, 3-30): lower case `a-z 0-9 . _`, no `..`/`__`,
  /// starts and ends with a letter or digit (OQ-24).
  static ValidationError? username(String value) {
    final error = _check(
      value,
      min: 3,
      max: 30,
      allow: _username,
      transform: (v) => v.toLowerCase(),
    );
    if (error != null) return error;
    return _usernameRepeat.hasMatch(value.toLowerCase())
        ? ValidationError.format
        : null;
  }

  /// Email (SafeEmail, 254); compared in lower case.
  static ValidationError? email(String value) => _check(
    value,
    min: 3,
    max: 254,
    allow: _email,
    transform: (v) => v.toLowerCase(),
  );

  /// Sign-in password (SafePassword): 8-128, no markup; spaces are kept.
  static ValidationError? passwordLogin(String value) {
    if (value.isEmpty) return ValidationError.required;
    if (RejectPatterns.containsUnsafeContent(value)) {
      return ValidationError.unsafe;
    }
    final length = RejectPatterns.nfkc(value).runes.length;
    if (length < 8) return ValidationError.tooShort;
    if (length > 128) return ValidationError.tooLong;
    return null;
  }

  /// New password (sign-up, reset, change): sign-in rules plus an upper-case
  /// letter and a digit (OQ-29). The API also refuses common and reused
  /// passwords.
  static ValidationError? password(String value) {
    final error = passwordLogin(value);
    if (error != null) return error;
    return _upper.hasMatch(value) && _digit.hasMatch(value)
        ? null
        : ValidationError.weakPassword;
  }

  /// Confirmation field: same value as [original()] (read at validation time).
  static Validator confirmPassword(String Function() original) => (value) {
    if (value.isEmpty) return ValidationError.required;
    return value == original() ? null : ValidationError.mismatch;
  };

  /// 6-digit code (SafeOtp). Full-width digits are folded by NFKC.
  static ValidationError? otp(String value) =>
      _check(value, min: 6, max: 6, allow: _otp);

  /// Whole number within [min]..[max] (digits only; no sign, no spaces).
  static Validator integer({required int min, required int max}) => (value) {
    final v = normalise(value);
    if (v.isEmpty) return ValidationError.required;
    if (!_digits.hasMatch(v) || v.length > 9) return ValidationError.format;
    final n = int.parse(v);
    return n < min || n > max ? ValidationError.outOfRange : null;
  };

  /// Decimal within [min]..[max] with at most [decimals] places (`.` only).
  static Validator decimal({
    required num min,
    required num max,
    int decimals = 2,
  }) {
    final pattern = RegExp(
      decimals == 0 ? r'^[0-9]+$' : '^[0-9]{1,6}(\\.[0-9]{1,$decimals})?\$',
    );
    return (value) {
      final v = normalise(value);
      if (v.isEmpty) return ValidationError.required;
      if (!pattern.hasMatch(v)) return ValidationError.format;
      final n = double.parse(v);
      return n < min || n > max ? ValidationError.outOfRange : null;
    };
  }

  /// One-line text (SafeShortText(n), n <= 120).
  static Validator shortText({required int max}) =>
      (value) => _check(value, max: max, allow: _shortText);

  /// Multi-line text (SafeText(n), n <= 2000).
  static Validator freeText({required int max}) =>
      (value) => _check(value, max: max, allow: _text, multiline: true);

  /// Chat message (SafeChatMessage): text plus emoji; a zero-width joiner is
  /// allowed only inside an emoji sequence.
  static Validator chatMessage({int max = 2000}) =>
      (value) => _check(
        value,
        max: max,
        allow: _chat,
        multiline: true,
        allowEmojiZwj: true,
      );

  /// Search box (SafeSearchQuery, 64).
  static ValidationError? search(String value) =>
      _check(value, max: 64, allow: _search);

  /// People search by username prefix: at least 3 characters (doc 04 2.8).
  static ValidationError? usernameSearch(String value) => _check(
    value,
    min: 3,
    max: 30,
    allow: _usernamePrefix,
    transform: (v) => v.toLowerCase(),
  );

  /// Barcode digits (SafeBarcode: 8 or 12-14 digits with a valid GTIN check
  /// digit) or, when not all digits, a food search.
  static ValidationError? barcodeOrSearch(String value) {
    final v = normalise(value);
    if (!_digits.hasMatch(v)) return search(value);
    final validLength = v.length == 8 || (v.length >= 12 && v.length <= 14);
    return validLength && gtinValid(v) ? null : ValidationError.format;
  }

  static bool gtinValid(String digits) {
    final body = digits.substring(0, digits.length - 1);
    final check = int.parse(digits[digits.length - 1]);
    var total = 0;
    var i = 0;
    for (final d in body.split('').reversed) {
      total += int.parse(d) * (i.isEven ? 3 : 1);
      i++;
    }
    return (10 - total % 10) % 10 == check;
  }
}
