import 'dart:math' as math;

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/gps_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

const mLat = 1 / 111195.0;
final t0 = DateTime.utc(2026, 1, 1, 10);

TrackPoint fix(int sec, {double north = 0, double acc = 4}) => TrackPoint(
      lat: 38 + north * mLat,
      lon: 23.7,
      accuracyM: acc,
      time: t0.add(Duration(seconds: sec)),
    );

void main() {
  test('no fixes: searching, and counts how long', () {
    final r = GpsReadiness(startedAt: t0);
    expect(r.status(t0.add(const Duration(seconds: 7))), GpsSignal.searching);
    expect(r.searchingFor(t0.add(const Duration(seconds: 7))).inSeconds, 7);
  });

  test('steady accurate fixes for 10 s -> ready', () {
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 10; s++) {
      r.add(fix(s, north: (s.isEven ? 1 : -1).toDouble()));
    }
    expect(r.status(t0.add(const Duration(seconds: 10))), GpsSignal.ready);
  });

  test('accurate but still sliding toward the real spot -> settling', () {
    // Classic warm-up: claims +-4 m but moves 3 m every second.
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 12; s++) {
      r.add(fix(s, north: 40 - s * 3.0));
    }
    expect(r.status(t0.add(const Duration(seconds: 12))), GpsSignal.settling);
  });

  test('steady but inaccurate (+-15 m) -> settling', () {
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 12; s++) {
      r.add(fix(s, acc: 15));
    }
    expect(r.status(t0.add(const Duration(seconds: 12))), GpsSignal.settling);
  });

  test('ready needs a full 10 s of good fixes, not 5', () {
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 5; s++) {
      r.add(fix(s));
    }
    expect(r.status(t0.add(const Duration(seconds: 5))), GpsSignal.settling);
  });

  test('fixes stop for > 5 s -> back to searching, counts since last fix', () {
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 10; s++) {
      r.add(fix(s));
    }
    final at = t0.add(const Duration(seconds: 17));
    expect(r.status(at), GpsSignal.searching);
    expect(r.searchingFor(at).inSeconds, 7);
  });

  test('one bad fix inside the window drops back to settling', () {
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 10; s++) {
      r.add(fix(s, acc: s == 9 ? 30 : 4));
    }
    expect(r.status(t0.add(const Duration(seconds: 10))), GpsSignal.settling);
  });

  test('keeps only the last 2 minutes of fixes for the log', () {
    final r = GpsReadiness(startedAt: t0);
    for (var s = 0; s <= 300; s++) {
      r.add(fix(s));
    }
    expect(r.recent.length, lessThanOrEqualTo(121));
    expect(r.recent.first.time, t0.add(const Duration(seconds: 180)));
    expect(r.lastAccuracyM, 4);
  });

  test('spread is measured around the centre, not first-to-last', () {
    final r = GpsReadiness(startedAt: t0);
    final rnd = math.Random(1);
    for (var s = 0; s <= 10; s++) {
      r.add(fix(s, north: (rnd.nextDouble() - 0.5) * 6)); // +-3 m jitter
    }
    expect(r.status(t0.add(const Duration(seconds: 10))), GpsSignal.ready);
  });
}
