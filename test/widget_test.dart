import 'dart:async';
import 'dart:io';

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/kalman.dart';
import 'package:backtrack/main.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('record -> points -> stop flow', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bt_widget');
    final gps = StreamController<TrackPoint>.broadcast();
    // Built in the real zone: its write-chain futures must not depend on
    // the fake-async microtask queue, or awaiting them inside runAsync hangs.
    final rec = (await tester.runAsync(() async =>
        Recorder(
            store: TrackStore(dir),
            positions: () => gps.stream,
            smoother: PositionSmoother(processNoiseMps: 1e6))))!;

    await tester.pumpWidget(BacktrackApp(recorder: rec, showTiles: false));
    expect(find.text('Record'), findsOneWidget);
    expect(find.textContaining('Press Record'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('record')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.textContaining('Waiting for GPS'), findsOneWidget);
    expect(find.byKey(const Key('stop')), findsOneWidget);

    await tester.runAsync(() async {
      final t0 = DateTime.now().toUtc();
      gps.add(TrackPoint(lat: 37.980, lon: 23.73, accuracyM: 5, time: t0));
      gps.add(TrackPoint(
          lat: 37.981,
          lon: 23.73,
          accuracyM: 5,
          time: t0.add(const Duration(seconds: 60))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await rec.idle();
    });
    await tester.pump();
    expect(find.text('111 m'), findsWidgets); // distance + max gap
    expect(find.text('2'), findsOneWidget); // points

    await tester.tap(find.byKey(const Key('stop')));
    // Not pumpAndSettle: the 1 s duration ticker keeps scheduling frames.
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Stop')));
    await tester.pump(); // dialog pops -> stop() begins
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(rec.state, RecState.stopped);
    expect(find.text('New recording'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    rec.dispose();
    await gps.close();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold the session file; temp dir is harmless.
      }
    });
  });
}
