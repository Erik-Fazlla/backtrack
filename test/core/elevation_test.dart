import 'package:backtrack/core/elevation.dart';
import 'package:backtrack/core/geo.dart';
import 'package:flutter_test/flutter_test.dart';

const m = 1 / 111195.0; // one metre of latitude

/// Walk north 1 m per point with the given altitudes.
List<TrackPoint> walk(List<double?> alts) => [
      for (var i = 0; i < alts.length; i++)
        TrackPoint(
          lat: 38 + i * m,
          lon: 23.7,
          accuracyM: 3,
          altitudeM: alts[i],
          time: DateTime.utc(2026).add(Duration(seconds: i)),
        ),
    ];

void main() {
  group('elevationStats', () {
    test('no altitude data -> zeros, nulls', () {
      final s = elevationStats(walk([null, null, null]));
      expect(s.gainM, 0);
      expect(s.lossM, 0);
      expect(s.maxM, isNull);
      expect(s.minM, isNull);
    });

    test('steady climb of 50 m then descent of 20 m', () {
      final alts = [
        for (var i = 0; i <= 500; i++) 100 + i * 0.1, // +50 m over 500 m
        for (var i = 1; i <= 200; i++) 150 - i * 0.1, // -20 m over 200 m
      ];
      final s = elevationStats(walk(alts));
      expect(s.gainM, closeTo(50, 3));
      expect(s.lossM, closeTo(20, 3));
      expect(s.maxM, closeTo(150, 1));
      expect(s.minM, closeTo(100, 1));
    });

    test('GPS altitude noise on flat ground is not counted as climbing', () {
      // ±2.5 m zig-zag every point on a flat 600 m walk.
      final alts = [for (var i = 0; i < 600; i++) 200 + (i.isEven ? 2.5 : -2.5)];
      final s = elevationStats(walk(alts));
      expect(s.gainM, lessThan(4));
      expect(s.lossM, lessThan(4));
    });

    test('gaps in altitude are skipped', () {
      final alts = [
        for (var i = 0; i <= 300; i++) i % 10 == 0 ? null : 100 + i * 0.1,
      ];
      final s = elevationStats(walk(alts));
      expect(s.gainM, closeTo(30, 3));
    });
  });

  group('elevationProfile', () {
    test('distance along the trail vs altitude, downsampled', () {
      final alts = [for (var i = 0; i <= 1000; i++) 100 + i * 0.05];
      final prof = elevationProfile(walk(alts), maxSamples: 50);
      expect(prof.length, lessThanOrEqualTo(51));
      expect(prof.first.distanceM, 0);
      expect(prof.last.distanceM, closeTo(1000, 2));
      expect(prof.last.altitudeM, closeTo(150, 2));
    });

    test('empty when no altitudes', () {
      expect(elevationProfile(walk([null, null])), isEmpty);
    });
  });

  group('currentGrade', () {
    test('uphill 10 % over the last 50 m', () {
      final alts = [for (var i = 0; i <= 100; i++) 100 + i * 0.1];
      final g = currentGrade(walk(alts));
      expect(g, isNotNull);
      expect(g!, closeTo(10, 1.5));
      expect(gradeLabel(g), Slope.uphill);
    });

    test('downhill and flat labels', () {
      expect(gradeLabel(-6), Slope.downhill);
      expect(gradeLabel(1.5), Slope.flat);
      expect(gradeLabel(-2.9), Slope.flat);
    });

    test('null until 20 m walked or without altitude', () {
      expect(currentGrade(walk([100, 101, 102])), isNull);
      expect(currentGrade(walk(List.filled(100, null))), isNull);
    });
  });
}
