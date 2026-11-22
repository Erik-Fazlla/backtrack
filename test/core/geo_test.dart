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
}
