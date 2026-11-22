import 'geo.dart';

/// Drops GPS fixes that would draw a wrong trail:
/// poor accuracy, or a jump faster than a person can move.
class PointFilter {
  PointFilter({
    this.maxAccuracyM = 25,
    this.maxSpeedMps = 15,
    this.minSpacingM = 0,
  });

  final double maxAccuracyM;
  final double maxSpeedMps;

  /// GPS sends a fix every second; only save one when we've moved this far.
  /// Keeps the trail clean while standing still and the file small.
  final double minSpacingM;
  TrackPoint? _last;

  bool accept(TrackPoint p) {
    if (p.accuracyM > maxAccuracyM) return false;
    final last = _last;
    if (last != null) {
      final seconds = p.time.difference(last.time).inMilliseconds / 1000;
      final metres = distanceBetween(last, p);
      if (metres < minSpacingM) return false;
      // Guard tiny time deltas: treat as 1 s so a 2 m wobble is not a spike.
      final speed = metres / (seconds < 1 ? 1 : seconds);
      if (speed > maxSpeedMps) return false;
    }
    _last = p;
    return true;
  }

  void reset() => _last = null;
}
