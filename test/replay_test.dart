import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Replays a GPX walk through the real recording pipeline on the PC:
/// noise + GPS spikes in, trail out. No walk needed.
List<TrackPoint> loadGpx(String path) {
  final re = RegExp(
      r'<trkpt lat="([-\d.]+)" lon="([-\d.]+)">.*?<ele>([-\d.]+)</ele>.*?<time>([^<]+)</time>');
  return re.allMatches(File(path).readAsStringSync()).map((m) {
    return TrackPoint(
      lat: double.parse(m[1]!),
      lon: double.parse(m[2]!),
      altitudeM: double.parse(m[3]!),
      accuracyM: 5,
      time: DateTime.parse(m[4]!),
    );
  }).toList();
}

/// Shift a point by (north, east) metres.
TrackPoint shift(TrackPoint p, double n, double e, {double? acc}) {
  const mPerDeg = 111195.0;
  return TrackPoint(
    lat: p.lat + n / mPerDeg,
    lon: p.lon + e / (mPerDeg * math.cos(p.lat * math.pi / 180)),
    altitudeM: p.altitudeM,
    accuracyM: acc ?? p.accuracyM,
    time: p.time,
  );
}

double gaussian(math.Random r) =>
    math.sqrt(-2 * math.log(1 - r.nextDouble())) *
    math.cos(2 * math.pi * r.nextDouble());

void main() {
  final truth = loadGpx('test/fixtures/block_loop.gpx');
  const trueLengthM = 540.0;

  Future<Recorder> replay(List<TrackPoint> fixes) async {
    final dir = Directory.systemTemp.createTempSync('bt_replay');
    addTearDown(() => dir.deleteSync(recursive: true));
    final gps = StreamController<TrackPoint>.broadcast();
    final rec = Recorder(store: TrackStore(dir), positions: () => gps.stream);
    await rec.start();
    for (final f in fixes) {
      gps.add(f);
    }
    await Future<void>.delayed(Duration.zero);
    await rec.stop();
    await gps.close();
    return rec;
  }

  test('fixture is the expected 540 m loop', () {
    expect(truth.length, greaterThan(300));
    expect(trailDistance(truth), closeTo(trueLengthM, 5));
  });

  test('clean replay keeps distance, corners and closes the loop', () async {
    final rec = await replay(truth);
    expect(rec.distanceM, closeTo(trueLengthM, trueLengthM * 0.05));
    expect(maxGap(rec.points), lessThan(10));
    expect(distanceBetween(rec.points.first, rec.points.last), lessThan(5));
  });

  test('realistic GPS noise (σ 3 m) + spikes still gives a usable trail',
      () async {
    final r = math.Random(42);
    final noisy = <TrackPoint>[];
    for (var i = 0; i < truth.length; i++) {
      var p = shift(truth[i], gaussian(r) * 3, gaussian(r) * 3,
          acc: 4 + r.nextDouble() * 6);
      if (i == 100) p = shift(p, 150, 0); // multipath jump 150 m
      if (i == 200) p = shift(p, 0, 80, acc: 60); // bad-accuracy fix
      noisy.add(p);
    }
    final rec = await replay(noisy);

    // Distance: noise adds a little zig-zag, must stay within 15 %.
    expect(rec.distanceM, closeTo(trueLengthM, trueLengthM * 0.15));
    // No holes in the trail.
    expect(maxGap(rec.points), lessThan(50));
    // Spikes never made it into the trail: every saved point is
    // within 15 m of the true route.
    for (final p in rec.points) {
      final nearest =
          truth.map((t) => distanceBetween(t, p)).reduce(math.min);
      expect(nearest, lessThan(15), reason: 'point off-route: $nearest m');
    }
    // Each 90° corner is still visible: a saved point within 8 m of it.
    final corners = [truth[0], truth[85], truth[192], truth[277]];
    for (final c in corners) {
      final nearest =
          rec.points.map((p) => distanceBetween(c, p)).reduce(math.min);
      expect(nearest, lessThan(8), reason: 'corner lost: $nearest m');
    }
  });
}
