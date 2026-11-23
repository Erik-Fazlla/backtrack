import 'dart:math' as math;

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/path_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

const lat0 = 38.0, lon0 = 23.7;
const mLat = 1 / 111195.0;
final mLon = 1 / (111195.0 * math.cos(lat0 * math.pi / 180));

(double, double) ll(double n, double e) => (lat0 + n * mLat, lon0 + e * mLon);

TrackPoint at(double n, double e, int sec) => TrackPoint(
      lat: lat0 + n * mLat,
      lon: lon0 + e * mLon,
      accuracyM: 4,
      time: DateTime.utc(2026).add(Duration(seconds: sec)),
    );

PathLine line(List<(double, double)> neList) =>
    PathLine([for (final (n, e) in neList) ll(n, e)]);

/// Distance in metres from a point to the nearest of the lines.
double distToLines(TrackPoint p, List<PathLine> lines) {
  // Exact point-to-segment distance in local metres.
  (double, double) xy(double lat, double lon) =>
      ((lon - lon0) / mLon, (lat - lat0) / mLat);
  final q = xy(p.lat, p.lon);
  var best = double.infinity;
  for (final l in lines) {
    for (var i = 0; i < l.points.length - 1; i++) {
      final a = xy(l.points[i].$1, l.points[i].$2);
      final b = xy(l.points[i + 1].$1, l.points[i + 1].$2);
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      var t = ((q.$1 - a.$1) * dx + (q.$2 - a.$2) * dy) / (dx * dx + dy * dy);
      t = t.clamp(0.0, 1.0);
      best = math.min(
          best,
          math.sqrt(math.pow(q.$1 - (a.$1 + t * dx), 2) +
              math.pow(q.$2 - (a.$2 + t * dy), 2)));
    }
  }
  return best;
}

void main() {
  // Street running east, from -100 m to 300 m.
  final street = line([(0, -100), (0, 300)]);

  test('walk 12 m beside a street is pulled onto it', () {
    final r = math.Random(3);
    final trail = [
      for (var i = 0; i <= 40; i++)
        at(12 + (r.nextDouble() - 0.5) * 4, i * 5.0, i * 4),
    ];
    final snapped = snapToPaths(trail, [street]);
    expect(snapped.length, trail.length);
    for (final p in snapped) {
      expect(distToLines(p, [street]), lessThan(1));
    }
  });

  test('no path within 20 m: trail is left exactly as recorded', () {
    final trail = [for (var i = 0; i <= 20; i++) at(45, i * 5.0, i * 4)];
    final snapped = snapToPaths(trail, [street]);
    for (var i = 0; i < trail.length; i++) {
      expect(snapped[i].lat, trail[i].lat);
      expect(snapped[i].lon, trail[i].lon);
    }
  });

  test('turning at a crossroads follows both streets', () {
    final northSt = line([(-100, 150), (300, 150)]); // runs north at e=150
    // East along the street (8 m north of it), then north (8 m east of it).
    final trail = [
      for (var i = 0; i <= 28; i++) at(8, i * 5.0, i * 4),
      for (var i = 1; i <= 20; i++) at(8 + i * 5.0, 158, 112 + i * 4),
    ];
    final snapped = snapToPaths(trail, [street, northSt]);
    // First leg on the east street, last leg on the north street.
    for (final p in snapped.take(20)) {
      expect(distToLines(p, [street]), lessThan(1));
    }
    for (final p in snapped.skip(trail.length - 15)) {
      expect(distToLines(p, [northSt]), lessThan(1));
    }
  });

  test('crossing a road at right angles does not slide along it', () {
    // Walking north across the east-running street.
    final trail = [for (var i = -10; i <= 10; i++) at(i * 4.0, 50, i + 10)];
    final snapped = snapToPaths(trail, [street]);
    // Points well away from the crossing keep their own north position.
    for (var i = 0; i < trail.length; i++) {
      final n = (trail[i].lat - lat0) / mLat;
      final sn = (snapped[i].lat - lat0) / mLat;
      if (n.abs() > 10) expect((sn - n).abs(), lessThan(0.01));
      // East position never drifts along the road.
      final se = (snapped[i].lon - lon0) / mLon;
      expect((se - 50).abs(), lessThan(1));
    }
  });

  test('leaving the path into the forest: only the path part snaps', () {
    final trail = [
      for (var i = 0; i <= 20; i++) at(6, i * 5.0, i * 4), // along street
      for (var i = 1; i <= 20; i++) at(6 + i * 5.0, 100, 80 + i * 4), // north, no path
    ];
    final snapped = snapToPaths(trail, [street]);
    for (final p in snapped.take(18)) {
      expect(distToLines(p, [street]), lessThan(1));
    }
    for (var i = trail.length - 15; i < trail.length; i++) {
      expect(snapped[i].lat, trail[i].lat);
      expect(snapped[i].lon, trail[i].lon);
    }
  });

  test('picks the nearer of two parallel streets', () {
    final far = line([(30, -100), (30, 300)]);
    final trail = [for (var i = 0; i <= 30; i++) at(9, i * 5.0, i * 4)];
    final snapped = snapToPaths(trail, [street, far]);
    for (final p in snapped) {
      expect(distToLines(p, [street]), lessThan(1));
    }
  });

  test('keeps time, accuracy and altitude of each point', () {
    final t = TrackPoint(
        lat: lat0 + 5 * mLat,
        lon: lon0,
        accuracyM: 7,
        altitudeM: 321,
        time: DateTime.utc(2026, 1, 1, 9));
    final s = snapToPaths([t, at(5, 5, 4), at(5, 10, 8)], [street]).first;
    expect(s.accuracyM, 7);
    expect(s.altitudeM, 321);
    expect(s.time, t.time);
  });

  test('empty inputs', () {
    expect(snapToPaths([], [street]), isEmpty);
    final one = [at(5, 0, 0)];
    expect(snapToPaths(one, []).single.lat, one.single.lat);
  });
}
