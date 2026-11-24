import 'package:flutter/material.dart';

/// The border of every text field and dropdown: a filled box with rounded
/// corners whose floating label stays INSIDE the box.
///
/// `OutlineInputBorder` puts the floating label on the top edge (half inside,
/// half outside the grey fill), which looked like the label overlapped the
/// field (owner 2026-11-24, Edit Profile). Reporting [isOutline] as false
/// makes the decorator lay the label out like a filled field, inside the
/// content padding. [borderSide] is drawn round the whole box (focus and
/// error colours); `BorderSide.none` draws nothing.
class NcFilledInputBorder extends InputBorder {
  const new({
    super.borderSide = BorderSide.none,
    this.borderRadius = BorderRadius.zero,
  });

  final BorderRadius borderRadius;

  @override
  bool get isOutline => false;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  NcFilledInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
  }) => NcFilledInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
  );

  @override
  NcFilledInputBorder scale(double t) => NcFilledInputBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(borderRadius.resolve(textDirection).toRRect(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()
    ..addRRect(
      borderRadius
          .resolve(textDirection)
          .toRRect(rect)
          .deflate(borderSide.width),
    );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none || borderSide.width == 0) return;
    final rrect = borderRadius
        .resolve(textDirection)
        .toRRect(rect)
        .deflate(borderSide.width / 2);
    canvas.drawRRect(rrect, borderSide.toPaint());
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is NcFilledInputBorder) {
      return NcFilledInputBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is NcFilledInputBorder) {
      return NcFilledInputBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) =>
      other is NcFilledInputBorder &&
      other.borderSide == borderSide &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(borderSide, borderRadius);
}
