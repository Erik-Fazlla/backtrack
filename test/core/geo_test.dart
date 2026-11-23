import 'package:backtrack/core/geo.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint p(double lat, double lon, {double acc = 5, int sec = 0}) =>
    TrackPoint(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
    );

void main() {
  group('distanceMeters', () {
    test('zero for same point', () {
      expect(distanceMeters(37.98, 23.73, 37.98, 23.73), 0);
    });

    test('one degree of latitude is about 111.2 km', () {
      expect(distanceMeters(0, 0, 1, 0), closeTo(111195, 50));
    });

    test('short distance in Athens is accurate to a metre', () {
      // 0.001 deg latitude ~ 111.2 m
      expect(distanceMeters(37.980, 23.730, 37.981, 23.730),
          closeTo(111.2, 1));
    });
  });

  group('TrackPoint json', () {
    test('round-trips through json', () {
      final a = TrackPoint(
        lat: 37.9,
        lon: 23.7,
        accuracyM: 4.5,
        altitudeM: 120.5,
        time: DateTime.utc(2026, 11, 22, 10),
      );
      final b = TrackPoint.fromJson(a.toJson());
      expect(b.lat, a.lat);
      expect(b.lon, a.lon);
      expect(b.accuracyM, a.accuracyM);
      expect(b.altitudeM, a.altitudeM);
      expect(b.time, a.time);
    });
  });

  group('trailDistance and maxGap', () {
    test('empty and single point trails', () {
      expect(trailDistance([]), 0);
      expect(trailDistance([p(0, 0)]), 0);
      expect(maxGap([p(0, 0)]), 0);
    });

    test('sums segments and finds largest gap', () {
      final pts = [
        p(37.980, 23.730),
        p(37.981, 23.730), // +111 m
        p(37.981, 23.730), // +0
        p(37.983, 23.730), // +222 m
      ];
      expect(trailDistance(pts), closeTo(333.6, 2));
      expect(maxGap(pts), closeTo(222.4, 1));
    });
  });

  group('extrapolate (smooth blue dot between fixes)', () {
    TrackPoint moving({double? spd = 2, double? hdg = 0}) => TrackPoint(
          lat: 37.98,
          lon: 23.73,
          accuracyM: 3,
          speedMps: spd,
          headingDeg: hdg,
          time: DateTime.utc(2026),
        );

    test('walking north 2 m/s: 0.5 s later is 1 m north', () {
      final e = extrapolate(moving(), const Duration(milliseconds: 500));
      expect(distanceMeters(37.98, 23.73, e.lat, e.lon), closeTo(1, 0.01));
      expect(e.lat, greaterThan(37.98));
      expect(e.lon, closeTo(23.73, 1e-9));
    });

    test('heading 90 moves east', () {
      final e = extrapolate(moving(hdg: 90), const Duration(seconds: 1));
      expect(e.lon, greaterThan(23.73));
      expect(e.lat, closeTo(37.98, 1e-9));
    });

    test('never runs ahead more than the max time', () {
      final e = extrapolate(moving(), const Duration(seconds: 10));
      expect(distanceMeters(37.98, 23.73, e.lat, e.lon), closeTo(3, 0.01));
    });

    test('standing still or unknown heading: stays put', () {
      for (final p in [moving(spd: 0.2), moving(hdg: null), moving(spd: null)]) {
        final e = extrapolate(p, const Duration(seconds: 1));
        expect(e.lat, p.lat);
        expect(e.lon, p.lon);
      }
    });

    test('speed and heading survive json', () {
      final p = TrackPoint.fromJson(moving(spd: 1.2, hdg: 45).toJson());
      expect(p.speedMps, 1.2);
      expect(p.headingDeg, 45);
    });
  });
}
