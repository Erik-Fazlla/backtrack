import 'package:backtrack/core/geo.dart';
import 'package:backtrack/services/journey_repo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const m = 1 / 111195.0;

List<TrackPoint> walk(int metres, {double startLat = 38, int startSec = 0,
    double alt0 = 100, double climbPerM = 0}) => [
      for (var i = 0; i <= metres; i += 5)
        TrackPoint(
          lat: startLat + i * m,
          lon: 23.7,
          accuracyM: 3,
          altitudeM: alt0 + i * climbPerM,
          time: DateTime.utc(2026, 11, 20).add(Duration(seconds: startSec + i)),
        ),
    ];

void main() {
  sqfliteFfiInit();
  late JourneyRepo repo;

  setUp(() async {
    repo = await JourneyRepo.open(inMemoryDatabasePath,
        factory: databaseFactoryFfi);
  });
  tearDown(() => repo.close());

  test('seeds the default categories with colours', () async {
    final cats = await repo.categories();
    expect(cats.map((c) => c.name),
        ['Run', 'Hike', 'Walk', 'Bike', 'Other']);
    expect(cats.every((c) => c.color != 0), isTrue);
  });

  test('save computes stats and keeps every point', () async {
    final hike = (await repo.categories()).firstWhere((c) => c.name == 'Hike');
    final pts = walk(500, climbPerM: 0.1); // 500 m, +50 m
    final id = await repo.save(name: 'Parnitha', categoryId: hike.id, points: pts);
    final j = (await repo.journey(id))!;
    expect(j.name, 'Parnitha');
    expect(j.categoryId, hike.id);
    expect(j.distanceM, closeTo(500, 1));
    expect(j.durationS, 500);
    expect(j.gainM, closeTo(50, 4));
    expect(j.startedAt, pts.first.time);
    final back = await repo.points(id);
    expect(back.length, pts.length);
    expect(back.last.lat, closeTo(pts.last.lat, 1e-9));
    expect(back.last.altitudeM, closeTo(150, 1e-6));
  });

  test('list filters by category, searches by name, sorts', () async {
    final cats = await repo.categories();
    final run = cats.firstWhere((c) => c.name == 'Run').id;
    final hike = cats.firstWhere((c) => c.name == 'Hike').id;
    await repo.save(name: 'Morning run', categoryId: run, points: walk(300));
    await repo.save(
        name: 'Long hike', categoryId: hike, points: walk(2000, startSec: 9999));
    await repo.save(
        name: 'Short hike', categoryId: hike, points: walk(100, startSec: 99999));

    final hikes = await repo.list(categoryIds: {hike});
    expect(hikes.map((j) => j.name), ['Short hike', 'Long hike']); // newest first

    final search = await repo.list(query: 'HIKE');
    expect(search.length, 2);

    final byDist = await repo.list(sort: JourneySort.distance);
    expect(byDist.first.name, 'Long hike');
  });

  test('rename, change category, delete', () async {
    final cats = await repo.categories();
    final id = await repo.save(
        name: 'x', categoryId: cats.first.id, points: walk(50));
    await repo.rename(id, 'Beach walk');
    await repo.setCategory(id, cats[2].id);
    final j = (await repo.journey(id))!;
    expect(j.name, 'Beach walk');
    expect(j.categoryId, cats[2].id);
    await repo.delete(id);
    expect(await repo.journey(id), isNull);
    expect(await repo.points(id), isEmpty);
  });

  test('category colour can be changed and a category added', () async {
    final c = (await repo.categories()).first;
    await repo.setCategoryColor(c.id, 0xFF123456);
    expect((await repo.categories()).first.color, 0xFF123456);
    await repo.addCategory('Ski', 0xFF00AAFF);
    expect((await repo.categories()).last.name, 'Ski');
  });

  test('category can be renamed', () async {
    final c = (await repo.categories()).first;
    await repo.renameCategory(c.id, '  Trail run ');
    expect((await repo.categories()).first.name, 'Trail run');
  });

  test('deleting a category moves its journeys to another one', () async {
    final cats = await repo.categories();
    final ski = await repo.addCategory('Ski', 0xFF00AAFF);
    final id = await repo.save(name: 's', categoryId: ski, points: walk(100));
    expect(await repo.journeyCount(ski), 1);
    await repo.deleteCategory(ski, moveTo: cats.last.id);
    expect((await repo.categories()).any((c) => c.id == ski), isFalse);
    expect((await repo.journey(id))!.categoryId, cats.last.id);
  });

  test('the last category cannot be deleted', () async {
    final cats = await repo.categories();
    for (final c in cats.skip(1)) {
      await repo.deleteCategory(c.id, moveTo: cats.first.id);
    }
    expect(() => repo.deleteCategory(cats.first.id, moveTo: cats.first.id),
        throwsStateError);
  });

  test('bounding box stored for fast map culling', () async {
    final cats = await repo.categories();
    final id = await repo.save(
        name: 'b', categoryId: cats.first.id, points: walk(1000));
    final j = (await repo.journey(id))!;
    expect(j.minLat, closeTo(38, 1e-9));
    expect(j.maxLat, closeTo(38 + 1000 * m, 1e-9));
  });

  test('refuses to save fewer than 2 points', () async {
    final cats = await repo.categories();
    expect(
      () => repo.save(name: 'x', categoryId: cats.first.id, points: walk(0)),
      throwsArgumentError,
    );
  });
}
