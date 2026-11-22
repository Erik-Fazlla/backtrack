import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/point_filter.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint p(double lat, double lon, {double acc = 5, int sec = 0}) =>
    TrackPoint(
      lat: lat,
      lon: lon,
      accuracyM: acc,
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
    );

void main() {
  test('first good point is accepted', () {
    final f = PointFilter();
    expect(f.accept(p(37.98, 23.73)), isTrue);
  });

  test('rejects points with poor accuracy', () {
    final f = PointFilter(maxAccuracyM: 25);
    expect(f.accept(p(37.98, 23.73, acc: 40)), isFalse);
    expect(f.accept(p(37.98, 23.73, acc: 25)), isTrue);
  });

  test('rejects a spike faster than walking/running speed', () {
    final f = PointFilter(maxSpeedMps: 15);
    expect(f.accept(p(37.980, 23.730, sec: 0)), isTrue);
    // 1.1 km in 10 s = 110 m/s -> spike
    expect(f.accept(p(37.990, 23.730, sec: 10)), isFalse);
    // 111 m in 30 s = 3.7 m/s -> ok
    expect(f.accept(p(37.981, 23.730, sec: 30)), isTrue);
  });

  test('spike check compares to last accepted point, not rejected one', () {
    final f = PointFilter(maxSpeedMps: 15);
    f.accept(p(37.980, 23.730, sec: 0));
    f.accept(p(37.990, 23.730, sec: 10)); // rejected spike
    // close to the first point again: fine
    expect(f.accept(p(37.9802, 23.730, sec: 20)), isTrue);
  });

  test('a long pause then far point is accepted (time makes speed sane)', () {
    final f = PointFilter(maxSpeedMps: 15);
    f.accept(p(37.980, 23.730, sec: 0));
    // 1.1 km after 10 minutes = 1.85 m/s
    expect(f.accept(p(37.990, 23.730, sec: 600)), isTrue);
  });

  test('skips points closer than minSpacing to the last saved one', () {
    final f = PointFilter(minSpacingM: 3);
    expect(f.accept(p(37.98000, 23.73, sec: 0)), isTrue);
    // ~1.1 m away -> standing still / jitter, not saved
    expect(f.accept(p(37.98001, 23.73, sec: 1)), isFalse);
    // ~4.4 m from the first -> saved
    expect(f.accept(p(37.98004, 23.73, sec: 3)), isTrue);
  });

  test('reset forgets the last point', () {
    final f = PointFilter(maxSpeedMps: 15);
    f.accept(p(37.980, 23.730, sec: 0));
    f.reset();
    expect(f.accept(p(37.990, 23.730, sec: 1)), isTrue);
  });
}
