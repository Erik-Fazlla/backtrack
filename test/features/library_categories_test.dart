import 'package:backtrack/app_services.dart';
import 'package:backtrack/features/journeys/library_screen.dart';
import 'package:backtrack/services/journey_repo.dart';
import 'package:backtrack/services/recorder.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io';

void main() {
  sqfliteFfiInit();

  testWidgets('add, then delete, a custom category in the Library',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final dir = Directory.systemTemp.createTempSync('bt_cat');
    final (rec, repo) = (await tester.runAsync(() async => (
          Recorder(
              store: TrackStore(dir),
              positions: () => const Stream.empty()),
          await JourneyRepo.open(inMemoryDatabasePath,
              factory: databaseFactoryFfi),
        )))!;
    final services = AppServices(recorder: rec, repo: repo, showTiles: false);

    Future<void> settle([int rounds = 6]) async {
      for (var i = 0; i < rounds; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.pumpWidget(
        MaterialApp(home: LibraryScreen(services: services)));
    await settle();

    final chips = find
        .descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable))
        .first;
    Future<void> reveal(Key k) =>
        tester.scrollUntilVisible(find.byKey(k), 150, scrollable: chips);

    // Add "Ski".
    await reveal(const Key('add_category'));
    await tester.tap(find.byKey(const Key('add_category')));
    await tester.pumpAndSettle();
    expect(find.text('New category'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('category_name')), 'Ski');
    await tester.pump();
    await tester.tap(find.byKey(const Key('category_save')));
    await settle();
    await reveal(const Key('filter_Ski'));
    expect(find.byKey(const Key('filter_Ski')), findsOneWidget);

    // Duplicate names are refused.
    await tester.drag(chips, const Offset(-2000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add_category')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('category_name')), 'hike');
    await tester.pump();
    expect(find.text('Already exists'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // Long-press -> delete.
    await reveal(const Key('filter_Ski'));
    await tester.longPress(find.byKey(const Key('filter_Ski')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('category_delete')));
    await settle();
    await tester.pumpAndSettle();
    expect(find.text('No journeys use it.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('category_delete_confirm')));
    await settle();
    expect(find.byKey(const Key('filter_Ski'), skipOffstage: false), findsNothing);
    expect(find.text('Ski'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    rec.dispose();
    await tester.runAsync(() async {
      await repo.close();
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // harmless
      }
    });
  });
}
