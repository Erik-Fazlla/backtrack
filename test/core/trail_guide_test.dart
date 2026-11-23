import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/trail_guide.dart';
import 'package:flutter_test/flutter_test.dart';

const mLat = 1 / 111195.0;
const lat0 = 38.0, lon0 = 23.7;
final mLon = 1 / (111195.0 * 0.7880107536067219); // cos(38°)

TrackPoint at(double northM, double eastM, {int sec = 0}) => TrackPoint(
      lat: lat0 + northM * mLat,
      lon: lon0 + eastM * mLon,
      accuracyM: 3,
      time: DateTime.utc(2026).add(Duration(seconds: sec)),
    );

void main() {
  // L-shaped trail: 100 m north, then 100 m east.
  final trail = [
    for (var n = 0; n <= 100; n += 10) at(n.toDouble(), 0),
    for (var e = 10; e <= 100; e += 10) at(100, e.toDouble()),
  ];

  group('TrailGuide.locate', () {
    final g = TrailGuide(trail);

    test('length', () => expect(g.lengthM, closeTo(200, 0.5)));

    test('on the trail: ~0 m off, along-distance correct', () {
      final r = g.locate(at(50, 0));
      expect(r.offTrailM, closeTo(0, 0.5));
      expect(r.alongM, closeTo(50, 0.5));
      expect(r.progress, closeTo(0.25, 0.01));
    });

    test('beside the trail: perpendicular distance', () {
      final r = g.locate(at(30, -25)); // 25 m west of first leg
      expect(r.offTrailM, closeTo(25, 0.5));
      expect(r.alongM, closeTo(30, 0.5));
    });

    test('second leg', () {
      final r = g.locate(at(110, 60)); // 10 m north of east leg
      expect(r.offTrailM, closeTo(10, 0.5));
      expect(r.alongM, closeTo(160, 0.5));
    });

    test('remaining distance back to the start is along the trail', () {
      final r = g.locate(at(100, 60));
      expect(r.alongM, closeTo(160, 0.5));
      expect(g.remainingM(r, towardStart: true), closeTo(160, 0.5));
      expect(g.remainingM(r, towardStart: false), closeTo(40, 0.5));
    });
  });

  group('pointAtAlong (where the arrow aims)', () {
    final g = TrailGuide(trail);

    test('interpolates along the trail and clamps at the ends', () {
      final p = g.pointAtAlong(130); // 30 m into the east leg
      expect(distanceBetween(p, at(100, 30)), lessThan(0.5));
      expect(distanceBetween(g.pointAtAlong(-50), trail.first), lessThan(0.5));
      expect(distanceBetween(g.pointAtAlong(999), trail.last), lessThan(0.5));
    });

    test('heading back: aims 30 m behind you along the trail', () {
      final here = g.locate(at(100, 60));
      final aim = g.aimPoint(here, towardStart: true, aheadM: 30);
      expect(distanceBetween(aim, at(100, 30)), lessThan(0.5));
      final aimEnd = g.aimPoint(here, towardStart: false, aheadM: 30);
      expect(distanceBetween(aimEnd, at(100, 90)), lessThan(0.5));
    });
  });

  group('bearing', () {
    test('compass directions', () {
      expect(bearingDeg(at(0, 0), at(100, 0)), closeTo(0, 0.5));
      expect(bearingDeg(at(0, 0), at(0, 100)), closeTo(90, 0.5));
      expect(bearingDeg(at(0, 0), at(-100, 0)), closeTo(180, 0.5));
      expect(bearingDeg(at(0, 0), at(0, -100)), closeTo(270, 0.5));
    });

    test('arrow angle relative to where you face', () {
      // target north, facing east -> arrow points left (-90)
      expect(relativeAngle(0, 90), closeTo(-90, 0.01));
      expect(relativeAngle(350, 10), closeTo(-20, 0.01));
      expect(relativeAngle(10, 350), closeTo(20, 0.01));
    });
  });

  group('OffTrailMonitor', () {
    test('alerts only after being far for a while, clears with hysteresis',
        () {
      final m = OffTrailMonitor(alertM: 30, clearM: 20, holdSeconds: 10);
      final t0 = DateTime.utc(2026);
      DateTime t(int s) => t0.add(Duration(seconds: s));

      expect(m.update(35, t(0)), isFalse); // just stepped off
      expect(m.update(36, t(5)), isFalse);
      expect(m.update(40, t(10)), isTrue); // 10 s far -> alert
      expect(m.update(25, t(12)), isTrue); // between 20 and 30: still off
      expect(m.update(15, t(14)), isFalse); // back on trail
    });

    test('brief GPS jump does not alert', () {
      final m = OffTrailMonitor(alertM: 30, clearM: 20, holdSeconds: 10);
      final t0 = DateTime.utc(2026);
      expect(m.update(45, t0), isFalse);
      expect(m.update(5, t0.add(const Duration(seconds: 2))), isFalse);
      expect(m.update(45, t0.add(const Duration(seconds: 4))), isFalse);
      expect(m.update(45, t0.add(const Duration(seconds: 12))), isFalse);
      expect(m.update(45, t0.add(const Duration(seconds: 14))), isTrue);
    });
  });
}
