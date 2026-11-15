import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Figma text styles (H1..H4, Body Large/Regular/Small, Caption, Footnote)
/// mapped onto Material's TextTheme so standard widgets pick them up. Sizes
/// scale with the user's text size; the app clamps the scale to 130 % (doc 02
/// section 1.4).
abstract final class NcTypography {
  static TextTheme textTheme(NcTheme nc) {
    TextStyle style(double size, FontWeight weight, Color color) => TextStyle(
      fontFamily: NcTypeScale.fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.3,
    );
    return TextTheme(
      displaySmall: style(NcTypeScale.h1, FontWeight.w700, nc.textPrimary),
      headlineMedium: style(NcTypeScale.h2, FontWeight.w700, nc.textPrimary),
      headlineSmall: style(NcTypeScale.h3, FontWeight.w600, nc.textPrimary),
      titleLarge: style(NcTypeScale.h4, FontWeight.w600, nc.textPrimary),
      bodyLarge: style(NcTypeScale.bodyLarge, FontWeight.w400, nc.textBody),
      bodyMedium: style(NcTypeScale.bodyRegular, FontWeight.w400, nc.textBody),
      bodySmall: style(NcTypeScale.bodySmall, FontWeight.w400, nc.textBody),
      labelLarge: style(NcTypeScale.bodyRegular, FontWeight.w600, nc.textBody),
      labelMedium: style(
        NcTypeScale.caption,
        FontWeight.w500,
        nc.textSecondary,
      ),
      labelSmall: style(
        NcTypeScale.footnote,
        FontWeight.w400,
        nc.textSecondary,
      ),
    );
  }
}
