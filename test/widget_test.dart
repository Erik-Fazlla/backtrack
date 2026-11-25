import 'dart:async';
import 'dart:io';

import 'package:backtrack/app_services.dart';
import 'package:backtrack/core/geo.dart';
import 'package:backtrack/core/gps_gate.dart';
import 'package:backtrack/core/kalman.dart';
import 'package:backtrack/main.dart';
import 'package:backtrack/services/journey_repo.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('record -> stop -> save -> library -> detail -> follow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('bt_widget');
    final gps = StreamController<TrackPoint>.broadcast();
    // Built in the real zone: their futures must not depend on the
    // fake-async microtask queue, or awaiting them inside runAsync hangs.
    final (rec, repo) = (await tester.runAsync(() async => (
          Recorder(
              store: TrackStore(dir),
              positions: () => gps.stream,
              smoother: PositionSmoother(processNoiseMps: 1e6),
              warmup: GpsWarmup(requiredFixes: 1, maxAccuracyM: 25)),
          await JourneyRepo.open(inMemoryDatabasePath,
              factory: databaseFactoryFfi),
        )))!;
    final services = AppServices(recorder: rec, repo: repo, showTiles: false);

    /// Let real IO (files, sqlite) and frames both make progress.
    Future<void> settle([int rounds = 8]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(BacktrackApp(services: services));
    expect(find.byKey(const Key('record')), findsOneWidget);
    expect(find.textContaining('until GPS is green'), findsOneWidget);

    // --- record ---------------------------------------------------------
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('record')));
      for (var i = 0; i < 100 && rec.state != RecState.waitingForFix; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pump();
    expect(find.textContaining('Getting an accurate position'), findsOneWidget);

    await tester.runAsync(() async {
      final t0 = DateTime.now().toUtc();
      gps.add(TrackPoint(
          lat: 37.980, lon: 23.73, accuracyM: 5, altitudeM: 100, time: t0));
      gps.add(TrackPoint(
          lat: 37.981,
          lon: 23.73,
          accuracyM: 5,
          altitudeM: 110,
          time: t0.add(const Duration(seconds: 60))));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await rec.idle();
    });
    await tester.pump();
    expect(find.text('111 m'), findsWidgets); // distance + max gap
    expect(find.text('2'), findsOneWidget); // points

    // --- stop -----------------------------------------------------------
    await tester.tap(find.byKey(const Key('stop')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Stop')));
    await settle();
    expect(rec.state, RecState.stopped);
    expect(find.byKey(const Key('take_me_back')), findsOneWidget);
    expect(find.byKey(const Key('save_journey')), findsOneWidget);

    // --- save -----------------------------------------------------------
    await tester.tap(find.byKey(const Key('save_journey')));
    await settle();
    expect(find.byKey(const Key('journey_name')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('journey_name')), 'Park loop');
    await tester.tap(find.byKey(const Key('cat_Hike')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save_journey_confirm')));
    await settle();
    expect(find.text('Saved'), findsOneWidget);
    final saved = (await tester.runAsync(() => repo.list()))!;
    expect(saved.single.name, 'Park loop');

    // --- library --------------------------------------------------------
    await tester.tap(find.text('Library'));
    await settle();
    expect(find.text('Park loop'), findsOneWidget);
    await tester.tap(find.text('Park loop'));
    await settle(12);
    expect(find.text('Elevation'), findsOneWidget);
    await tester.dragUntilVisible(find.byKey(const Key('follow_start')),
        find.byType(ListView).last, const Offset(0, -200));
    await tester.ensureVisible(find.byKey(const Key('follow_start')));
    // Let the "Saved to your Library" snackbar time out; it sits on top.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Follow to start'), findsOneWidget);

    // --- follow ---------------------------------------------------------
    await tester.tap(find.byKey(const Key('follow_start')));
    await settle();
    expect(find.text('Waiting for GPS…'), findsOneWidget);
    expect(find.text('To start'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    rec.dispose();
    await gps.close();
    await tester.runAsync(() async {
      await repo.close();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows may still hold the session file; temp dir is harmless.
      }
    });
  });
}
