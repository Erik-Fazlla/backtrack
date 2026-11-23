import 'dart:math' as math;

import 'geo.dart';

/// Where you are relative to a trail you are following.
class TrailPosition {
  const TrailPosition({
    required this.offTrailM,
    required this.alongM,
    required this.progress,
    required this.segment,
  });

  /// Shortest distance from you to the trail line.
  final double offTrailM;

  /// Distance from the trail's first point to your nearest spot on it.
  final double alongM;

  /// alongM / total length (0 = start, 1 = end).
  final double progress;

  /// Index of the nearest segment.
  final int segment;
}

/// Measures your position against a trail (follow-back / follow-saved).
/// Uses a local flat projection: exact enough for walks of tens of km.
class TrailGuide {
  TrailGuide(this.trail)
      : assert(trail.length >= 2),
        _lat0 = trail.first.lat,
        _cos = math.cos(trail.first.lat * math.pi / 180) {
    _xy = [for (final p in trail) _toXY(p.lat, p.lon)];
    _cum = [0];
    for (var i = 1; i < _xy.length; i++) {
      _cum.add(_cum.last + _dist(_xy[i - 1], _xy[i]));
    }
  }

  final List<TrackPoint> trail;
  final double _lat0;
  final double _cos;
  late final List<(double, double)> _xy;
  late final List<double> _cum;

  static const _m = 111195.0;

  (double, double) _toXY(double lat, double lon) =>
      ((lon - trail.first.lon) * _m * _cos, (lat - _lat0) * _m);

  static double _dist((double, double) a, (double, double) b) =>
      math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));

  double get lengthM => _cum.last;

  TrailPosition locate(TrackPoint p) {
    final q = _toXY(p.lat, p.lon);
    var best = double.infinity;
    var bestAlong = 0.0;
    var bestSeg = 0;
    for (var i = 0; i < _xy.length - 1; i++) {
      final a = _xy[i], b = _xy[i + 1];
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : ((q.$1 - a.$1) * dx + (q.$2 - a.$2) * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final proj = (a.$1 + t * dx, a.$2 + t * dy);
      final d = _dist(q, proj);
      if (d < best) {
        best = d;
        bestSeg = i;
        bestAlong = _cum[i] + t * math.sqrt(len2);
      }
    }
    return TrailPosition(
      offTrailM: best,
      alongM: bestAlong,
      progress: lengthM == 0 ? 0 : bestAlong / lengthM,
      segment: bestSeg,
    );
  }

  /// The point [alongM] metres from the trail's start (clamped to the ends).
  TrackPoint pointAtAlong(double alongM) {
    if (alongM <= 0) return trail.first;
    if (alongM >= lengthM) return trail.last;
    var i = 0;
    while (i < _cum.length - 2 && _cum[i + 1] < alongM) {
      i++;
    }
    final segLen = _cum[i + 1] - _cum[i];
    final t = segLen == 0 ? 0.0 : (alongM - _cum[i]) / segLen;
    final a = trail[i], b = trail[i + 1];
    return TrackPoint(
      lat: a.lat + (b.lat - a.lat) * t,
      lon: a.lon + (b.lon - a.lon) * t,
      accuracyM: 0,
      time: a.time,
    );
  }

  /// Where the guidance arrow should point: [aheadM] further along the
  /// trail toward the start or the end — follow the path you came by
  /// rather than a straight line through unknown terrain.
  TrackPoint aimPoint(TrailPosition pos,
          {required bool towardStart, double aheadM = 30}) =>
      pointAtAlong(towardStart ? pos.alongM - aheadM : pos.alongM + aheadM);

  /// Distance still to walk along the trail to the start or the end.
  double remainingM(TrailPosition pos, {required bool towardStart}) =>
      towardStart ? pos.alongM : lengthM - pos.alongM;
}

/// Compass bearing from [a] to [b], degrees clockwise from north (0-360).
double bearingDeg(TrackPoint a, TrackPoint b) {
  final f1 = a.lat * math.pi / 180, f2 = b.lat * math.pi / 180;
  final dl = (b.lon - a.lon) * math.pi / 180;
  final y = math.sin(dl) * math.cos(f2);
  final x = math.cos(f1) * math.sin(f2) -
      math.sin(f1) * math.cos(f2) * math.cos(dl);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// How far to turn from where you face to the target, -180..180
/// (negative = turn left).
double relativeAngle(double targetBearing, double facingDeg) {
  var d = (targetBearing - facingDeg) % 360;
  if (d > 180) d -= 360;
  if (d < -180) d += 360;
  return d;
}

/// Off-trail alarm with debounce and hysteresis: alert after being more than
/// [alertM] away for [holdSeconds]; clear once back within [clearM].
class OffTrailMonitor {
  OffTrailMonitor({this.alertM = 30, this.clearM = 20, this.holdSeconds = 10});

  final double alertM;
  final double clearM;
  final int holdSeconds;

  DateTime? _farSince;
  bool _alert = false;
  bool get alert => _alert;

  bool update(double offTrailM, DateTime now) {
    if (offTrailM > alertM) {
      _farSince ??= now;
      if (now.difference(_farSince!).inSeconds >= holdSeconds) _alert = true;
    } else {
      _farSince = null;
      if (offTrailM <= clearM) _alert = false;
    }
    return _alert;
  }

  void reset() {
    _farSince = null;
    _alert = false;
  }
}
