import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:naraacare/core/theme/app_theme.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// Onboarding progress bar whose filled part has a wavy top edge (Figma
/// onboarding header). [value] is 0..1.
class WaveProgress extends StatelessWidget {
  const new({required this.value, super.key});

  final double value;

  @override
  Widget build(BuildContext context) {
    final nc = context.nc;
    return Semantics(
      value: '${(value * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(NcRadius.full),
        child: SizedBox(
          height: NcSpace.buttonGap,
          child: CustomPaint(
            painter: _WavePainter(
              value: value.clamp(0, 1),
              fill: nc.primary,
              track: nc.primarySurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  const new({required this.value, required this.fill, required this.track});

  final double value;
  final Color fill;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final width = size.width * value;
    if (width <= 0) return;
    final amplitude = size.height * 0.15;
    final path = Path()..moveTo(0, size.height);
    for (var x = 0.0; x <= width; x += 1) {
      final y = amplitude + amplitude * math.sin(x / size.height * math.pi);
      path.lineTo(x, y);
    }
    path
      ..lineTo(width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.value != value || old.fill != fill || old.track != track;
}
