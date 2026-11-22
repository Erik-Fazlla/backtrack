import 'dart:ui';

import 'package:backtrack/core/projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('single point sits in the centre', () {
    final pr = TrailProjection.fit(
        [(lat: 37.98, lon: 23.73)], const Size(200, 400), padding: 20);
    final o = pr.toScreen(37.98, 23.73);
    expect(o.dx, closeTo(100, 0.01));
    expect(o.dy, closeTo(200, 0.01));
  });

  test('north is up and east is right', () {
    final pts = [(lat: 37.980, lon: 23.730), (lat: 37.981, lon: 23.731)];
    final pr = TrailProjection.fit(pts, const Size(300, 300), padding: 10);
    final sw = pr.toScreen(37.980, 23.730);
    final ne = pr.toScreen(37.981, 23.731);
    expect(ne.dx, greaterThan(sw.dx));
    expect(ne.dy, lessThan(sw.dy));
  });

  test('whole trail fits inside padding and keeps true proportions', () {
    // 111 m north-south, ~88 m east-west at lat 38
    final pts = [(lat: 37.980, lon: 23.730), (lat: 37.981, lon: 23.731)];
    final pr = TrailProjection.fit(pts, const Size(300, 300),
        padding: 10, minMetresAcross: 0);
    final a = pr.toScreen(37.980, 23.730);
    final b = pr.toScreen(37.981, 23.731);
    for (final o in [a, b]) {
      expect(o.dx, inInclusiveRange(10, 290));
      expect(o.dy, inInclusiveRange(10, 290));
    }
    final w = (b.dx - a.dx).abs();
    final h = (b.dy - a.dy).abs();
    expect(w / h, closeTo(87.7 / 111.2, 0.02));
    expect(h, closeTo(280, 0.5)); // taller side fills the box
  });

  test('metresPerPixel is enforced as a minimum zoom', () {
    final pts = [(lat: 37.98, lon: 23.73), (lat: 37.98001, lon: 23.73)];
    final pr = TrailProjection.fit(pts, const Size(200, 200),
        padding: 0, minMetresAcross: 100);
    // 100 m across 200 px -> 0.5 m/px
    expect(pr.metresPerPixel, closeTo(0.5, 0.01));
  });
}
