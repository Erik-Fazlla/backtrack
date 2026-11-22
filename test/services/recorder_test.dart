import 'dart:async';
import 'dart:io';

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/kalman.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint p(double lat, {double acc = 5, int sec = 0}) => TrackPoint(
      lat: lat,
      lon: 23.73,
      accuracyM: acc,
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
    );

void main() {
  late Directory dir;
  late StreamController<TrackPoint> gps;
  late Recorder rec;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('bt_rec');
    gps = StreamController<TrackPoint>.broadcast();
    rec = Recorder(
      store: TrackStore(dir),
      positions: () => gps.stream,
      // pass-through: these tests check the pipeline, not smoothing
      smoother: PositionSmoother(processNoiseMps: 1e6),
      now: () => DateTime.utc(2026, 1, 1),
    );
  });
  tearDown(() async {
    await rec.idle();
    rec.dispose();
    await gps.close();
    dir.deleteSync(recursive: true);
  });

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await rec.idle();
  }

  test('starts idle', () {
    expect(rec.state, RecState.idle);
    expect(rec.points, isEmpty);
  });

  test('waits for a good fix before recording', () async {
    await rec.start();
    expect(rec.state, RecState.waitingForFix);
    gps.add(p(37.98, acc: 80));
    await pump();
    expect(rec.state, RecState.waitingForFix);
    expect(rec.lastAccuracyM, 80);
    gps.add(p(37.98, acc: 8, sec: 2));
    await pump();
    expect(rec.state, RecState.recording);
    expect(rec.points.length, 1);
  });

  test('records filtered points and persists them', () async {
    await rec.start();
    gps.add(p(37.980, sec: 0));
    gps.add(p(37.990, sec: 1)); // spike, dropped
    gps.add(p(37.9805, sec: 20));
    await pump();
    expect(rec.points.length, 2);
    expect(rec.distanceM, closeTo(55.6, 1));

    final stored = await TrackStore(dir).loadLatest();
    expect(stored!.points.length, 2);
  });

  test('stop finishes the session and ignores later fixes', () async {
    await rec.start();
    gps.add(p(37.980));
    await pump();
    await rec.stop();
    gps.add(p(37.9801, sec: 10));
    await pump();
    expect(rec.state, RecState.stopped);
    expect(rec.points.length, 1);
    expect((await TrackStore(dir).loadLatest())!.finished, isTrue);
  });

  test('restore reloads an unfinished session and keeps recording', () async {
    await rec.start();
    gps.add(p(37.980));
    await pump();
    // app killed: new recorder on same storage
    final rec2 = Recorder(
      store: TrackStore(dir),
      positions: () => gps.stream,
      // pass-through: these tests check the pipeline, not smoothing
      smoother: PositionSmoother(processNoiseMps: 1e6),
      now: () => DateTime.utc(2026, 1, 1),
    );
    final resumed = await rec2.restore();
    expect(resumed, isTrue);
    expect(rec2.state, RecState.recording);
    expect(rec2.points.length, 1);
    gps.add(p(37.9802, sec: 30));
    await pump();
    await rec2.idle();
    expect(rec2.points.length, 2);
    rec2.dispose();
  });

  test('restore shows a finished session as stopped', () async {
    await rec.start();
    gps.add(p(37.980));
    await pump();
    await rec.stop();
    final rec2 = Recorder(
      store: TrackStore(dir),
      positions: () => gps.stream,
      // pass-through: these tests check the pipeline, not smoothing
      smoother: PositionSmoother(processNoiseMps: 1e6),
      now: () => DateTime.utc(2026, 1, 1),
    );
    expect(await rec2.restore(), isFalse);
    expect(rec2.state, RecState.stopped);
    expect(rec2.points.length, 1);
    rec2.dispose();
  });
}
