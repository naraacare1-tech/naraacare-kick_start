import 'package:flutter/widgets.dart';

/// Screen-size scaling (owner 2026-11-24: "logo, images and text should be
/// based on phone screen size").
///
/// The Figma frames are 390 dp wide (iOS) and 412 dp (Android, doc 02
/// section 1.1). The scale is the phone's short side against 390 dp, kept
/// between [minScreenScale] and [maxScreenScale] so a small phone stays
/// readable and a tablet does not blow up. Text, logos and avatar art use
/// it. Spacing, buttons and touch targets stay fixed (doc 02 section 1.2:
/// 56 dp buttons, 48 dp targets).
const double designWidth = 390;
const double minScreenScale = 0.85;
const double maxScreenScale = 1.3;

/// Text grows less than images: on top of the user's own text size (up to
/// 130 %) a tablet would otherwise reach 170 % and break layouts.
const double maxTextScreenScale = 1.15;

/// The screen part of the app-wide text scale.
double textScreenScaleFor(Size size) =>
    screenScaleFor(size).clamp(minScreenScale, maxTextScreenScale);

/// The scale for a screen of [size] (logical pixels).
double screenScaleFor(Size size) => size.shortestSide <= 0
    ? 1
    : (size.shortestSide / designWidth).clamp(minScreenScale, maxScreenScale);

extension NcResponsive on BuildContext {
  /// The screen scale of this phone; 1.0 on a 390 dp wide phone.
  double get screenScale => screenScaleFor(MediaQuery.sizeOf(this));

  /// [dp] from the Figma frame, scaled to this phone.
  double scaled(double dp) => dp * screenScale;
}
