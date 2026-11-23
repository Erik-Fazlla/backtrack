import 'dart:math' as math;

import 'geo.dart';

/// Climb/descent summary of a trail.
class ElevationStats {
  const ElevationStats({
    required this.gainM,
    required this.lossM,
    required this.maxM,
    required this.minM,
  });
  final double gainM;
  final double lossM;
  final double? maxM;
  final double? minM;

  static const empty =
      ElevationStats(gainM: 0, lossM: 0, maxM: null, minM: null);
}

class ProfilePoint {
  const ProfilePoint(this.distanceM, this.altitudeM);
  final double distanceM;
  final double altitudeM;
}

/// Altitude smoothed over [windowM] metres of walking (GPS altitude is noisy:
/// a few metres up and down every second even on flat ground).
List<ProfilePoint> _smoothed(List<TrackPoint> pts, {double windowM = 30}) {
  final raw = <ProfilePoint>[];
  var d = 0.0;
  TrackPoint? prev;
  for (final p in pts) {
    if (prev != null) d += distanceBetween(prev, p);
    prev = p;
    final a = p.altitudeM;
    if (a != null) raw.add(ProfilePoint(d, a));
  }
  if (raw.isEmpty) return const [];
  final out = <ProfilePoint>[];
  var lo = 0;
  var hi = 0;
  var sum = 0.0;
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i].distanceM;
    while (hi < raw.length && raw[hi].distanceM <= c + windowM / 2) {
      sum += raw[hi].altitudeM;
      hi++;
    }
    while (raw[lo].distanceM < c - windowM / 2) {
      sum -= raw[lo].altitudeM;
      lo++;
    }
    out.add(ProfilePoint(c, sum / (hi - lo)));
  }
  return out;
}

/// Total climb and descent. Only changes bigger than [thresholdM] count, so
/// leftover noise doesn't add up to fake hills.
ElevationStats elevationStats(List<TrackPoint> pts, {double thresholdM = 3}) {
  final s = _smoothed(pts);
  if (s.isEmpty) return ElevationStats.empty;
  var gain = 0.0, loss = 0.0;
  var ref = s.first.altitudeM;
  var maxA = ref, minA = ref;
  for (final p in s) {
    final a = p.altitudeM;
    maxA = math.max(maxA, a);
    minA = math.min(minA, a);
    final diff = a - ref;
    if (diff >= thresholdM) {
      gain += diff;
      ref = a;
    } else if (diff <= -thresholdM) {
      loss -= diff;
      ref = a;
    }
  }
  return ElevationStats(gainM: gain, lossM: loss, maxM: maxA, minM: minA);
}

/// Distance-vs-altitude points for the chart, at most [maxSamples] (+ end).
List<ProfilePoint> elevationProfile(List<TrackPoint> pts,
    {int maxSamples = 200}) {
  final s = _smoothed(pts);
  if (s.length <= maxSamples) return s;
  final step = (s.length - 1) / maxSamples;
  return [for (var k = 0; k <= maxSamples; k++) s[(k * step).round()]];
}

/// Slope over the last [overM] metres walked, in percent (+ = uphill).
/// Null until at least 20 m with altitude has been walked.
double? currentGrade(List<TrackPoint> pts, {double overM = 50}) {
  final s = _smoothed(pts);
  if (s.length < 2) return null;
  final end = s.last;
  var i = s.length - 1;
  while (i > 0 && end.distanceM - s[i].distanceM < overM) {
    i--;
  }
  final run = end.distanceM - s[i].distanceM;
  if (run < 20) return null;
  return (end.altitudeM - s[i].altitudeM) / run * 100;
}

enum Slope { uphill, downhill, flat }

Slope gradeLabel(double gradePct) => gradePct > 3
    ? Slope.uphill
    : gradePct < -3
        ? Slope.downhill
        : Slope.flat;
