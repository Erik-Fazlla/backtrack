import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/path_matcher.dart';
import 'package:backtrack/services/path_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local-only checks against the real Greece map and real walks
/// (maps/ and test/real_logs/ are git-ignored). Skipped when absent.
List<TrackPoint> loadRaw(String path) => File(path)
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => jsonDecode(l) as Map<String, Object?>)
    .where((j) => j.containsKey('lat'))
    .map(TrackPoint.fromJson)
    .toList();

double distToPaths(TrackPoint p, List<PathLine> lines) {
  final c = math.cos(p.lat * math.pi / 180);
  (double, double) xy(double lat, double lon) =>
      ((lon - p.lon) * 111195 * c, (lat - p.lat) * 111195);
  var best = double.infinity;
  for (final l in lines) {
    for (var i = 0; i < l.points.length - 1; i++) {
      final a = xy(l.points[i].$1, l.points[i].$2);
      final b = xy(l.points[i + 1].$1, l.points[i + 1].$2);
      final dx = b.$1 - a.$1, dy = b.$2 - a.$2;
      final len2 = dx * dx + dy * dy;
      if (len2 == 0) continue;
      final t = ((-a.$1) * dx + (-a.$2) * dy) / len2;
      final tt = t.clamp(0.0, 1.0);
      best = math.min(best,
          math.sqrt(math.pow(a.$1 + tt * dx, 2) + math.pow(a.$2 + tt * dy, 2)));
    }
  }
  return best;
}

void main() {
  final map = File('maps/greece.pmtiles');
  final street = File('test/real_logs/session_20261123_124027.jsonl');

  test('reads real roads around a trail from the Greece map', () async {
    final src = await PathSource.open(map.path);
    addTearDown(src.close);
    final athens = [
      TrackPoint(lat: 37.9838, lon: 23.7275, accuracyM: 3, time: DateTime.utc(2026)),
      TrackPoint(lat: 37.9850, lon: 23.7290, accuracyM: 3, time: DateTime.utc(2026)),
    ];
    final lines = await src.around(athens);
    expect(lines.length, greaterThan(20));
    for (final l in lines) {
      for (final (la, lo) in l.points) {
        expect(la, inInclusiveRange(37.97, 38.0));
        expect(lo, inInclusiveRange(23.71, 23.75));
      }
    }
  }, skip: !map.existsSync() ? 'maps/greece.pmtiles not downloaded' : false);

  test('real street walk: snapping moves the trail onto the street',
      () async {
    final trail = loadRaw(street.path);
    final src = await PathSource.open(map.path);
    addTearDown(src.close);
    final lines = await src.around(trail);
    final snapped = snapToPaths(trail, lines);

    double mean(List<TrackPoint> pts) =>
        pts.map((p) => distToPaths(p, lines)).reduce((a, b) => a + b) /
        pts.length;
    final before = mean(trail), after = mean(snapped);
    final onPath = snapped.where((p) => distToPaths(p, lines) < 0.5).length;
    // ignore: avoid_print
    print('street walk: ${lines.length} path lines, mean distance to a path '
        '${before.toStringAsFixed(1)} m -> ${after.toStringAsFixed(1)} m, '
        '$onPath/${snapped.length} points on a path');
    expect(after, lessThan(before / 2));

    // For eyeballing: tools/plot_snap.py draws this.
    Directory('test/real_logs/out').createSync(recursive: true);
    File('test/real_logs/out/street_snap.json').writeAsStringSync(jsonEncode({
      'lines': [
        for (final l in lines) [for (final (la, lo) in l.points) [la, lo]],
      ],
      'raw': [for (final p in trail) [p.lat, p.lon]],
      'snapped': [for (final p in snapped) [p.lat, p.lon]],
    }));
  },
      skip: !map.existsSync() || !street.existsSync()
          ? 'needs maps/greece.pmtiles and the real street-walk log'
          : false);
}
