import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naraacare/core/errors/error_messages.dart';
import 'package:naraacare/core/l10n/generated/app_localizations.dart';
import 'package:naraacare/core/security/input_validators.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// The ONLY text input widget of the app (doc 07 section 4.3). A test fails
/// if `TextField`/`TextFormField` is used anywhere else in lib/.
///
/// * [validator] and [maxLength] are required, so every field is validated
///   and length-capped (the API applies the same rules again).
/// * Error text comes from fixed copy; it never repeats what was typed.
/// * Secret fields turn off suggestions, autocorrect and personalised
///   learning (doc 07 SEC-5.10).
class NcTextField extends StatefulWidget {
  const new({
    required this.validator,
    required this.maxLength,
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.keyboardType,
    this.inputFormatters = const [],
    this.textInputAction,
    this.autofillHints,
    this.secret = false,
    this.enabled = true,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.maxLines = 1,
    this.minLines,
    this.textAlign = TextAlign.start,
    this.style,
    this.showCursor,
    this.decoration,
    this.serverError,
  });

  final Validator validator;
  final int maxLength;
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool secret;
  final bool enabled;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final int maxLines;

  /// Lines shown before the field grows (up to [maxLines]); null = maxLines.
  final int? minLines;
  final TextAlign textAlign;
  final TextStyle? style;
  final bool? showCursor;

  /// Replaces the default decoration (used by `NcOtpInput`); error text
  /// still comes from [validator].
  final InputDecoration? decoration;

  /// A message for this field from the API (already localised fixed copy).
  final String? serverError;

  /// Digits only (OTP, ages).
  static final TextInputFormatter digitsOnly =
      FilteringTextInputFormatter.digitsOnly;

  /// Numbers with up to two decimals: `^\d*\.?\d{0,2}$` (doc 07 4.3).
  static final decimal = FilteringTextInputFormatter.allow(
    RegExp(r'^\d*\.?\d{0,2}'),
  );

  /// Username characters, lower-cased as typed.
  static final List<TextInputFormatter> username = [
    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9._]')),
    TextInputFormatter.withFunction(
      (oldValue, newValue) =>
          newValue.copyWith(text: newValue.text.toLowerCase()),
    ),
  ];

  @override
  State<NcTextField> createState() => _NcTextFieldState();
}

class _NcTextFieldState extends State<NcTextField> {
  bool _obscured = true;

  String? _validate(String? value) {
    final error = widget.validator(value ?? '');
    if (error == null) return null;
    return ErrorMessages.validation(AppLocalizations.of(context), error);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nc = context.nc;
    final secret = widget.secret;
    final decoration =
        (widget.decoration ??
                InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  helperText: widget.helper,
                  prefixIcon: widget.prefixIcon == null
                      ? null
                      : Icon(widget.prefixIcon, size: NcSize.icon),
                  suffixIcon: secret
                      ? IconButton(
                          tooltip: _obscured
                              ? l10n.showPassword
                              : l10n.hidePassword,
                          icon: Icon(
                            _obscured ? Icons.visibility_off : Icons.visibility,
                            color: nc.textSecondary,
                          ),
                          onPressed: () =>
                              setState(() => _obscured = !_obscured),
                        )
                      : null,
                ))
            .copyWith(
              errorText: widget.serverError,
              errorMaxLines: 3,
              counterText: '',
            );
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      validator: _validate,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      maxLength: widget.maxLength,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      maxLines: secret ? 1 : widget.maxLines,
      minLines: secret ? null : widget.minLines,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      obscureText: secret && _obscured,
      enableSuggestions: !secret,
      autocorrect: !secret,
      enableIMEPersonalizedLearning: !secret,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      textAlign: widget.textAlign,
      style: widget.style,
      showCursor: widget.showCursor,
      decoration: decoration,
    );
  }
}
