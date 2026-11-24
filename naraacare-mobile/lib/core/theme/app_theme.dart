import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/nc_input_border.dart';
import 'package:naraacare/core/theme/tokens.dart';
import 'package:naraacare/core/theme/typography.dart';

/// NaraaCare tokens as a [ThemeExtension], read in widgets with `context.nc`.
/// Light theme only for the MVP (doc 02 section 1.3: dark mode is not
/// designed); the extension is the seam for a dark variant later.
@immutable
class NcTheme extends ThemeExtension<NcTheme> {
  const new({
    required this.primary,
    required this.primaryDisabled,
    required this.primarySurface,
    required this.star,
    required this.starGradientStart,
    required this.starGradientEnd,
    required this.success,
    required this.successSurface,
    required this.error,
    required this.errorSurface,
    required this.textPrimary,
    required this.textBody,
    required this.textSecondary,
    required this.inputFill,
    required this.border,
    required this.surface,
    required this.scrim,
    required this.screenPadding,
  });

  factory light({required TargetPlatform platform}) => NcTheme(
    primary: NcColors.primary,
    primaryDisabled: NcColors.primaryDisabled,
    primarySurface: NcColors.primarySurface,
    star: NcColors.star,
    starGradientStart: NcColors.starGradientStart,
    starGradientEnd: NcColors.starGradientEnd,
    success: NcColors.success,
    successSurface: NcColors.successSurface,
    error: NcColors.error,
    errorSurface: NcColors.errorSurface,
    textPrimary: NcColors.textPrimary,
    textBody: NcColors.textBody,
    textSecondary: NcColors.textSecondary,
    inputFill: NcColors.inputFill,
    border: NcColors.border,
    surface: NcColors.surface,
    scrim: NcColors.scrim,
    // Figma layout grid: 20 pt margins on iOS, 16 dp on Android.
    screenPadding: platform == TargetPlatform.iOS
        ? NcSpace.screenPaddingIos
        : NcSpace.screenPaddingAndroid,
  );

  final Color primary;
  final Color primaryDisabled;
  final Color primarySurface;
  final Color star;
  final Color starGradientStart;
  final Color starGradientEnd;
  final Color success;
  final Color successSurface;
  final Color error;
  final Color errorSurface;
  final Color textPrimary;
  final Color textBody;
  final Color textSecondary;
  final Color inputFill;
  final Color border;
  final Color surface;
  final Color scrim;
  final double screenPadding;

  @override
  NcTheme copyWith({Color? primary, double? screenPadding}) => NcTheme(
    primary: primary ?? this.primary,
    primaryDisabled: primaryDisabled,
    primarySurface: primarySurface,
    star: star,
    starGradientStart: starGradientStart,
    starGradientEnd: starGradientEnd,
    success: success,
    successSurface: successSurface,
    error: error,
    errorSurface: errorSurface,
    textPrimary: textPrimary,
    textBody: textBody,
    textSecondary: textSecondary,
    inputFill: inputFill,
    border: border,
    surface: surface,
    scrim: scrim,
    screenPadding: screenPadding ?? this.screenPadding,
  );

  @override
  NcTheme lerp(covariant ThemeExtension<NcTheme>? other, double t) => this;
}

extension NcThemeContext on BuildContext {
  NcTheme get nc => Theme.of(this).extension<NcTheme>()!;
}

abstract final class AppTheme {
  static ThemeData light({TargetPlatform? platform}) {
    final target = platform ?? defaultTargetPlatform;
    final nc = NcTheme.light(platform: target);
    final scheme = ColorScheme.fromSeed(
      seedColor: nc.primary,
      primary: nc.primary,
      error: nc.error,
      surface: nc.surface,
    );
    // Filled box, label inside it (not on the top edge; owner 2026-11-24).
    final inputBorder = NcFilledInputBorder(
      borderRadius: BorderRadius.circular(NcRadius.m),
    );
    return ThemeData(
      useMaterial3: true,
      platform: target,
      colorScheme: scheme,
      scaffoldBackgroundColor: nc.surface,
      fontFamily: NcTypeScale.fontFamily,
      textTheme: NcTypography.textTheme(nc),
      extensions: [nc],
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: nc.inputFill,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: nc.primary),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: nc.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: nc.error),
        ),
        hintStyle: TextStyle(color: nc.textSecondary),
        errorStyle: TextStyle(color: nc.error),
        // 12 dp top/bottom leaves room for the label inside the box.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: NcSpace.cardPadding,
          vertical: NcSpace.buttonGap,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: nc.primary,
          disabledBackgroundColor: nc.primaryDisabled,
          foregroundColor: nc.surface,
          disabledForegroundColor: nc.surface,
          minimumSize: const Size.fromHeight(NcSize.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(NcRadius.full),
          ),
        ),
      ),
    );
  }
}
