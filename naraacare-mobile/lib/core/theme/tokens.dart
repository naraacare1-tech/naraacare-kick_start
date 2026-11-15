import 'package:flutter/painting.dart';

/// Design tokens (doc 02 section 1). The ONLY place with colour and size
/// literals: widgets read them through `context.nc` (see app_theme.dart), and
/// a test fails when a hex colour appears anywhere else in lib/.
///
/// Colours are SAMPLED from the Figma PNG exports (OQ-01 open); replace them
/// with the Figma variables when they are exported. Spacing and sizes are exact
/// (Figma foundations page); the radius values are a proposal (names exact).
abstract final class NcColors {
  static const primary = Color(0xFF35AFF4);
  static const primaryDisabled = Color(0xFFC4D8E4);
  static const primarySurface = Color(0xFFE6F5FE);
  static const star = Color(0xFF684C9C);
  static const starGradientStart = Color(0xFFA78BFA);
  static const starGradientEnd = Color(0xFF6366F1);
  static const success = Color(0xFF19B27A);
  static const successSurface = Color(0xFFDDF5EC);
  static const error = Color(0xFFF87171);
  static const errorSurface = Color(0xFFFCF0F0);
  static const textPrimary = Color(0xFF111827);
  static const textBody = Color(0xFF344044);
  static const textSecondary = Color(0xFF6B7280);
  static const inputFill = Color(0xFFF2F2F7);
  static const border = Color(0xFFE5E7EB);
  static const surface = Color(0xFFFFFFFF);
  static const scrim = Color(0x99111827);
  // Avatar fill per tracker (owner, 2026-11-07): water, nutrition, sleep.
  static const avatarWater = Color(0xFF38BDF8);
  static const avatarNutrition = Color(0xFF22C55E);
  static const avatarSleep = Color(0xFF8B5CF6);
}

/// Spacing (doc 02 section 1.2).
abstract final class NcSpace {
  static const screenPaddingAndroid = 16.0;
  static const screenPaddingIos = 20.0;
  static const sectionGap = 32.0;
  static const cardGap = 16.0;
  static const cardPadding = 16.0;
  static const buttonGap = 12.0;
  static const inputGap = 8.0;
  static const xs = 4.0;
}

/// Sizes (doc 02 section 1.2).
abstract final class NcSize {
  static const buttonHeight = 56.0;
  static const onboardingTextMaxWidth = 320.0;
  static const otpBox = 48.0;
  static const bottomNavHeight = 64.0;
  static const iconSmall = 16.0;
  static const icon = 24.0;
  static const maxTextScale = 1.3;
}

/// Radius scale XXS..Full (names from Figma; values proposed, doc 02
/// section 1.2).
abstract final class NcRadius {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const s = 8.0;
  static const m = 12.0;
  static const l = 16.0;
  static const xl = 24.0;
  static const full = 999.0;
}

/// Type scale (doc 02 section 1.4, proposed until Figma sizes are exported).
abstract final class NcTypeScale {
  static const fontFamily = 'Manrope';
  static const h1 = 32.0;
  static const h2 = 28.0;
  static const h3 = 24.0;
  static const h4 = 20.0;
  static const bodyLarge = 18.0;
  static const bodyRegular = 16.0;
  static const bodySmall = 14.0;
  static const caption = 12.0;
  static const footnote = 11.0;
}
