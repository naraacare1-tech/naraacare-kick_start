import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:naraacare/core/theme/tokens.dart';

/// The four-colour Google "G", drawn in code (no image asset), for the
/// "Sign in with Google" button.
class GoogleLogo extends StatelessWidget {
  const new({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(size: Size.square(size), painter: const _GPainter()),
  );
}

class _GPainter extends CustomPainter {
  const new();

  static double _rad(double degrees) => degrees * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final radius = (size.width - stroke) / 2;
    final center = size.center(Offset.zero);
    final ring = Rect.fromCircle(center: center, radius: radius);
    Paint arc(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Angles: 0 is 3 o'clock, clockwise. The opening sits at the top right.
    canvas
      ..drawArc(ring, _rad(-145), _rad(105), false, arc(NcColors.googleRed))
      ..drawArc(ring, _rad(145), _rad(70), false, arc(NcColors.googleYellow))
      ..drawArc(ring, _rad(45), _rad(100), false, arc(NcColors.googleGreen))
      ..drawArc(ring, _rad(0), _rad(45), false, arc(NcColors.googleBlue))
      // The crossbar, from the middle to the outer edge.
      ..drawRect(
        Rect.fromLTRB(
          center.dx,
          center.dy - stroke / 2,
          size.width,
          center.dy + stroke / 2,
        ),
        Paint()..color = NcColors.googleBlue,
      );
  }

  @override
  bool shouldRepaint(_GPainter oldDelegate) => false;
}
