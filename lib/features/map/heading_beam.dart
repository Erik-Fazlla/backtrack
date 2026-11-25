import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/angles.dart';

/// Backtrack-orange light cone from the "you are here" dot, pointing where
/// the phone faces. Placed as a map Marker that rotates with the map, so
/// [headingDeg] is a plain compass bearing (0 = north).
class HeadingBeam extends StatelessWidget {
  const HeadingBeam({
    super.key,
    required this.headingDeg,
    this.accuracyDeg,
    this.size = 140,
  });

  final double headingDeg;
  final double? accuracyDeg;
  final double size;

  static const color = Color(0xFFFF6B00);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Transform.rotate(
          angle: headingDeg * math.pi / 180,
          child: CustomPaint(
            size: Size.square(size),
            painter: _BeamPainter(beamWidthDeg(accuracyDeg)),
          ),
        ),
      );
}

class _BeamPainter extends CustomPainter {
  _BeamPainter(this.widthDeg);
  final double widthDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final half = widthDeg / 2 * math.pi / 180;
    // Cone points "up" (north); the parent rotates it to the heading.
    final start = -math.pi / 2 - half;
    final path = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(Rect.fromCircle(center: c, radius: r), start, half * 2, false)
      ..close();
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          HeadingBeam.color.withValues(alpha: 0.55),
          HeadingBeam.color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.widthDeg != widthDeg;
}
