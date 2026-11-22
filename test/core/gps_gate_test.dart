import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/gps_gate.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint p(double lat,
        {double acc = 5, int sec = 0, double? speed, double lon = 23.73}) =>
    TrackPoint(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      speedMps: speed,
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
    );

const m = 1 / 111195; // one metre of latitude

void main() {
  group('GpsWarmup', () {
    test('not ready until enough good fixes agree', () {
      final w = GpsWarmup(requiredFixes: 3, maxAccuracyM: 15, maxSpreadM: 10);
      expect(w.feed(p(37.98, sec: 0)), isFalse);
      expect(w.feed(p(37.98 + 2 * m, sec: 1)), isFalse);
      expect(w.feed(p(37.98 + 1 * m, sec: 2)), isTrue);
      expect(w.ready, isTrue);
    });

    test('a poor-accuracy fix restarts the count', () {
      final w = GpsWarmup(requiredFixes: 3, maxAccuracyM: 15, maxSpreadM: 10);
      w.feed(p(37.98, sec: 0));
      w.feed(p(37.98, sec: 1));
      expect(w.feed(p(37.98, acc: 30, sec: 2)), isFalse);
      expect(w.feed(p(37.98, sec: 3)), isFalse);
      expect(w.feed(p(37.98, sec: 4)), isFalse);
      expect(w.feed(p(37.98, sec: 5)), isTrue);
    });

    test('fixes still converging (jumping around) are not trusted', () {
      // Classic cold start: position slides 30 m while settling.
      final w = GpsWarmup(requiredFixes: 3, maxAccuracyM: 15, maxSpreadM: 10);
      expect(w.feed(p(37.98, sec: 0)), isFalse);
      expect(w.feed(p(37.98 + 15 * m, sec: 1)), isFalse);
      expect(w.feed(p(37.98 + 30 * m, sec: 2)), isFalse);
      // settles
      expect(w.feed(p(37.98 + 31 * m, sec: 3)), isFalse);
      expect(w.feed(p(37.98 + 31 * m, sec: 4)), isTrue);
    });

    test('once ready stays ready', () {
      final w = GpsWarmup(requiredFixes: 1);
      expect(w.feed(p(37.98)), isTrue);
      expect(w.feed(p(37.98, acc: 80, sec: 1)), isTrue);
    });

    test('reset starts over', () {
      final w = GpsWarmup(requiredFixes: 1)..feed(p(37.98));
      w.reset();
      expect(w.ready, isFalse);
    });
  });

  group('isMoving', () {
    test('Doppler speed below threshold means standing still', () {
      expect(isMoving(p(37.98, speed: 0.1)), isFalse);
      expect(isMoving(p(37.98, speed: 0.4)), isFalse);
    });

    test('walking speed means moving', () {
      expect(isMoving(p(37.98, speed: 1.2)), isTrue);
    });

    test('unknown speed is treated as moving (spacing filter decides)', () {
      expect(isMoving(p(37.98)), isTrue);
    });
  });
}
