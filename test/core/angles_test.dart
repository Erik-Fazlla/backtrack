import 'package:backtrack/core/angles.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('first reading passes straight through', () {
    expect(smoothAngle(null, 123, 0.3), 123);
  });

  test('moves part of the way toward the new reading', () {
    expect(smoothAngle(0, 100, 0.5), closeTo(50, 1e-9));
  });

  test('takes the short way round across north', () {
    // 350 -> 10 should pass through 0, not swing through 180.
    final s = smoothAngle(350, 10, 0.5);
    expect(s, closeTo(0, 1e-9));
    final t = smoothAngle(10, 350, 0.5);
    expect(t, closeTo(0, 1e-9));
  });

  test('result stays within 0..360', () {
    for (final (a, b) in [(359.0, 1.0), (1.0, 359.0), (180.0, 181.0)]) {
      final s = smoothAngle(a, b, 0.3);
      expect(s, inInclusiveRange(0, 360));
    }
  });

  test('beam width follows compass accuracy, within limits', () {
    expect(beamWidthDeg(null), 60);
    expect(beamWidthDeg(5), 30);
    expect(beamWidthDeg(25), 50);
    expect(beamWidthDeg(200), 100);
  });
}
