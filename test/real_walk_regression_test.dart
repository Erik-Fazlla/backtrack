import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real phone walks (2026-11-23, a ~200 m loop around a park), shifted to a
/// fake location so the fixtures don't reveal where they were recorded.
/// Guards the pipeline against regressions on real GPS behaviour.
List<TrackPoint> load(String path) => File(path)
    .readAsLinesSync()
    .where((l) => l.trim().isNotEmpty)
    .map((l) => jsonDecode(l) as Map<String, Object?>)
    .where((j) => j.containsKey('lat'))
    .map(TrackPoint.fromJson)
    .toList();

void main() {
  for (final name in ['park_loop_satellites', 'park_loop_fused']) {
    test('real walk $name', () async {
      final raw = load('test/fixtures/$name.jsonl');
      final dir = Directory.systemTemp.createTempSync('bt_realwalk');
      addTearDown(() => dir.deleteSync(recursive: true));
      final gps = StreamController<TrackPoint>.broadcast();
      final rec = Recorder(store: TrackStore(dir), positions: () => gps.stream);
      await rec.start();
      for (final p in raw) {
        gps.add(p);
      }
      await Future<void>.delayed(Duration.zero);
      await rec.stop();
      await gps.close();

      final pts = rec.points;
      final rawLen = trailDistance(raw);
      // Trail starts within 10 s (warm-up while standing at the start).
      expect(pts.first.time.difference(raw.first.time).inSeconds,
          lessThanOrEqualTo(10));
      // Distance within 12 % of the raw path (smoothing trims jitter only).
      expect(rec.distanceM, closeTo(rawLen, rawLen * 0.12));
      // No holes.
      expect(maxGap(pts), lessThan(10));
      // Loop closes: walked back to the start.
      expect(distanceBetween(pts.first, pts.last), lessThan(8));
      // Trail never strays from what the GPS saw (no invented geometry).
      for (final p in pts) {
        final nearest = raw
            .map((r) => distanceBetween(r, p))
            .reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(4));
      }
    });
  }
}
