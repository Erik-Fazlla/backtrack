import 'package:backtrack/core/map_region.dart';
import 'package:flutter_test/flutter_test.dart';

MapRegion r(String name, double minLat, double minLon, double maxLat,
        double maxLon, {int size = 100 << 20}) =>
    MapRegion(
      name: name,
      path: '/maps/$name.pmtiles',
      minLat: minLat,
      minLon: minLon,
      maxLat: maxLat,
      maxLon: maxLon,
      maxZoom: 15,
      sizeBytes: size,
    );

void main() {
  final greece = r('greece', 34.7, 19.3, 41.8, 29.7);
  final attica = r('attica', 37.6, 23.3, 38.4, 24.1);
  final italy = r('italy', 36.6, 6.6, 47.1, 18.6);

  test('no regions -> no map', () {
    expect(pickRegion([], 38, 23.7), isNull);
  });

  test('picks the region containing the position', () {
    expect(pickRegion([greece, italy], 41.9, 12.5)!.name, 'italy');
    expect(pickRegion([greece, italy], 37.98, 23.73)!.name, 'greece');
  });

  test('prefers the smallest (most detailed) containing region', () {
    expect(pickRegion([greece, attica], 37.98, 23.73)!.name, 'attica');
    expect(pickRegion([greece, attica], 40.6, 22.9)!.name, 'greece');
  });

  test('unknown or outside position -> largest region as fallback', () {
    expect(pickRegion([attica, greece], null, null)!.name, 'greece');
    expect(pickRegion([attica, greece], 51.5, -0.1)!.name, 'greece');
  });

  test('size label', () {
    expect(r('a', 0, 0, 1, 1, size: 350 << 20).sizeLabel, '350 MB');
    expect(r('a', 0, 0, 1, 1, size: 3 << 30).sizeLabel, '3.0 GB');
  });
}
