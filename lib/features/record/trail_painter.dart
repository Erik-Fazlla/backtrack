import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../core/projection.dart';

/// Draws the trail on a plain grid: no map tiles needed (works offline).
class TrailPainter extends CustomPainter {
  TrailPainter({
    required this.points,
    required this.current,
    required this.trailColor,
    required this.gridColor,
    required this.startColor,
    required this.meColor,
  });

  final List<TrackPoint> points;
  final TrackPoint? current;
  final Color trailColor;
  final Color gridColor;
  final Color startColor;
  final Color meColor;

  static const double gridStepM = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final all = <LatLon>[
      for (final p in points) (lat: p.lat, lon: p.lon),
      if (current != null) (lat: current!.lat, lon: current!.lon),
    ];
    if (all.isEmpty) return;
    final pr = TrailProjection.fit(all, size, padding: 32);

    // Grid: one line every 50 m so distance can be judged without a map.
    final gridPx = gridStepM / pr.metresPerPixel;
    if (gridPx > 6) {
      final g = Paint()
        ..color = gridColor
        ..strokeWidth = 1;
      final origin = pr.toScreen(all.first.lat, all.first.lon);
      final x0 = origin.dx % gridPx;
      final y0 = origin.dy % gridPx;
      for (var x = x0; x < size.width; x += gridPx) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), g);
      }
      for (var y = y0; y < size.height; y += gridPx) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
      }
    }

    if (points.length > 1) {
      final path = Path();
      final first = pr.toScreen(points.first.lat, points.first.lon);
      path.moveTo(first.dx, first.dy);
      for (final p in points.skip(1)) {
        final o = pr.toScreen(p.lat, p.lon);
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = trailColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    if (points.isNotEmpty) {
      final s = pr.toScreen(points.first.lat, points.first.lon);
      canvas.drawCircle(s, 10, Paint()..color = Colors.white);
      canvas.drawCircle(s, 7, Paint()..color = startColor);
    }

    final me = current;
    if (me != null) {
      final o = pr.toScreen(me.lat, me.lon);
      final accPx = math.min(me.accuracyM / pr.metresPerPixel, size.shortestSide);
      canvas.drawCircle(o, accPx, Paint()..color = meColor.withValues(alpha: 0.15));
      canvas.drawCircle(o, 9, Paint()..color = Colors.white);
      canvas.drawCircle(o, 6, Paint()..color = meColor);
    }
  }

  @override
  bool shouldRepaint(TrailPainter old) => true;
}
