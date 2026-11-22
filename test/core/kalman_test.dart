import 'dart:math' as math;

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/kalman.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint p(double lat, double lon, {double acc = 5, int sec = 0}) =>
    TrackPoint(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
    );

void main() {
  test('first fix passes through unchanged', () {
    final k = PositionSmoother();
    final s = k.update(p(37.98, 23.73));
    expect(s.lat, 37.98);
    expect(s.lon, 23.73);
  });

  test('standing still with jitter stays close to the true spot', () {
    final k = PositionSmoother();
    final r = math.Random(1);
    TrackPoint? s;
    for (var i = 0; i < 60; i++) {
      final dLat = (r.nextDouble() - 0.5) * 2 * 5 / 111195; // ±5 m
      final dLon = (r.nextDouble() - 0.5) * 2 * 5 / 87700;
      s = k.update(p(37.98 + dLat, 23.73 + dLon, sec: i));
    }
    expect(distanceMeters(s!.lat, s.lon, 37.98, 23.73), lessThan(2.5));
  });

  test('follows real movement (no big lag at walking speed)', () {
    final k = PositionSmoother();
    TrackPoint? s;
    // walk north 1.4 m/s for 60 s
    for (var i = 0; i <= 60; i++) {
      s = k.update(p(37.98 + i * 1.4 / 111195, 23.73, sec: i));
    }
    final truthLat = 37.98 + 60 * 1.4 / 111195;
    expect(distanceMeters(s!.lat, s.lon, truthLat, 23.73), lessThan(3));
  });

  test('a less accurate fix moves the estimate less', () {
    final a = PositionSmoother()..update(p(37.98, 23.73, sec: 0));
    final b = PositionSmoother()..update(p(37.98, 23.73, sec: 0));
    final target = 37.98 + 20 / 111195;
    final good = a.update(p(target, 23.73, acc: 5, sec: 2));
    final bad = b.update(p(target, 23.73, acc: 20, sec: 2));
    expect(good.lat, greaterThan(bad.lat));
  });

  test('keeps accuracy, altitude and time of the raw fix', () {
    final k = PositionSmoother()..update(p(37.98, 23.73));
    final raw = TrackPoint(
        lat: 37.9801,
        lon: 23.73,
        accuracyM: 7,
        altitudeM: 99,
        time: DateTime.utc(2026, 1, 1, 0, 0, 3));
    final s = k.update(raw);
    expect(s.accuracyM, 7);
    expect(s.altitudeM, 99);
    expect(s.time, raw.time);
  });
}
