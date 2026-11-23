import 'dart:math' as math;

const double _earthRadiusM = 6371008.8;

/// One recorded GPS fix.
class TrackPoint {
  const TrackPoint({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.time,
    this.altitudeM,
    this.speedMps,
    this.headingDeg,
  });

  final double lat;
  final double lon;
  final double accuracyM;
  final double? altitudeM;

  /// Doppler speed from the GPS chip. Much more reliable than position
  /// changes for telling "standing still" from "walking".
  final double? speedMps;

  /// Direction of travel from the GPS chip, degrees clockwise from north.
  final double? headingDeg;
  final DateTime time;

  Map<String, Object?> toJson() => {
        'lat': lat,
        'lon': lon,
        'acc': accuracyM,
        'alt': altitudeM,
        if (speedMps != null) 'spd': speedMps,
        if (headingDeg != null) 'hdg': headingDeg,
        't': time.toUtc().millisecondsSinceEpoch,
      };

  factory TrackPoint.fromJson(Map<String, Object?> j) => TrackPoint(
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        accuracyM: (j['acc'] as num).toDouble(),
        altitudeM: (j['alt'] as num?)?.toDouble(),
        speedMps: (j['spd'] as num?)?.toDouble(),
        headingDeg: (j['hdg'] as num?)?.toDouble(),
        time: DateTime.fromMillisecondsSinceEpoch(j['t'] as int, isUtc: true),
      );
}

double _rad(double deg) => deg * math.pi / 180;

/// Great-circle distance in metres (haversine).
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(lat1)) *
          math.cos(_rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * _earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
}

double distanceBetween(TrackPoint a, TrackPoint b) =>
    distanceMeters(a.lat, a.lon, b.lat, b.lon);

/// Total length of the trail in metres.
double trailDistance(List<TrackPoint> pts) {
  var sum = 0.0;
  for (var i = 1; i < pts.length; i++) {
    sum += distanceBetween(pts[i - 1], pts[i]);
  }
  return sum;
}

/// Largest distance between two consecutive points, in metres.
/// Used by the M0 gate: no gap may exceed 50 m.
double maxGap(List<TrackPoint> pts) {
  var gap = 0.0;
  for (var i = 1; i < pts.length; i++) {
    gap = math.max(gap, distanceBetween(pts[i - 1], pts[i]));
  }
  return gap;
}

/// Where a moving person probably is [ahead] after fix [p] was taken:
/// moves along the GPS heading at the GPS speed. Used only to draw the
/// blue dot smoothly between the 1-per-second fixes; never saved.
/// Returns [p] unchanged when standing still or heading/speed is unknown.
TrackPoint extrapolate(TrackPoint p, Duration ahead,
    {Duration max = const Duration(milliseconds: 1500),
    double minSpeedMps = 0.5}) {
  final v = p.speedMps;
  final h = p.headingDeg;
  if (v == null || h == null || v < minSpeedMps || ahead <= Duration.zero) {
    return p;
  }
  final secs = (ahead > max ? max : ahead).inMilliseconds / 1000;
  final d = v * secs;
  final rad = h * math.pi / 180;
  final north = d * math.cos(rad);
  final east = d * math.sin(rad);
  return TrackPoint(
    lat: p.lat + north / 111195.0,
    lon: p.lon + east / (111195.0 * math.cos(p.lat * math.pi / 180)),
    accuracyM: p.accuracyM,
    altitudeM: p.altitudeM,
    speedMps: p.speedMps,
    headingDeg: p.headingDeg,
    time: p.time,
  );
}
