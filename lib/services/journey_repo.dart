import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import '../core/elevation.dart';
import '../core/geo.dart';

class Category {
  const Category(this.id, this.name, this.color);
  final int id;
  final String name;

  /// ARGB colour used for this category's lines and chips.
  final int color;
}

class Journey {
  const Journey({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceM,
    required this.durationS,
    required this.gainM,
    required this.lossM,
    required this.maxAltM,
    required this.minAltM,
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
  });

  final int id;
  final String name;
  final int categoryId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceM;
  final int durationS;
  final double gainM;
  final double lossM;
  final double? maxAltM;
  final double? minAltM;
  final double minLat, minLon, maxLat, maxLon;

  factory Journey._from(Map<String, Object?> r) => Journey(
        id: r['id'] as int,
        name: r['name'] as String,
        categoryId: r['category_id'] as int,
        startedAt:
            DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int, isUtc: true),
        endedAt:
            DateTime.fromMillisecondsSinceEpoch(r['ended_at'] as int, isUtc: true),
        distanceM: (r['distance_m'] as num).toDouble(),
        durationS: r['duration_s'] as int,
        gainM: (r['gain_m'] as num).toDouble(),
        lossM: (r['loss_m'] as num).toDouble(),
        maxAltM: (r['max_alt_m'] as num?)?.toDouble(),
        minAltM: (r['min_alt_m'] as num?)?.toDouble(),
        minLat: (r['min_lat'] as num).toDouble(),
        minLon: (r['min_lon'] as num).toDouble(),
        maxLat: (r['max_lat'] as num).toDouble(),
        maxLon: (r['max_lon'] as num).toDouble(),
      );
}

enum JourneySort { newest, distance, gain }

/// Saved journeys on the phone (SQLite). Nothing leaves the device.
class JourneyRepo {
  JourneyRepo._(this._db);
  final Database _db;

  static const defaultCategories = [
    ('Run', 0xFFFF6B00),
    ('Hike', 0xFF2E9E4F),
    ('Walk', 0xFF1E6FE8),
    ('Bike', 0xFF8E44AD),
    ('Other', 0xFF7F8C8D),
  ];

  static Future<JourneyRepo> open(String path,
      {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE categories(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              color INTEGER NOT NULL,
              sort INTEGER NOT NULL)''');
          await db.execute('''
            CREATE TABLE journeys(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              category_id INTEGER NOT NULL REFERENCES categories(id),
              started_at INTEGER NOT NULL,
              ended_at INTEGER NOT NULL,
              distance_m REAL NOT NULL,
              duration_s INTEGER NOT NULL,
              gain_m REAL NOT NULL,
              loss_m REAL NOT NULL,
              max_alt_m REAL,
              min_alt_m REAL,
              min_lat REAL NOT NULL, min_lon REAL NOT NULL,
              max_lat REAL NOT NULL, max_lon REAL NOT NULL)''');
          await db.execute('''
            CREATE TABLE points(
              journey_id INTEGER NOT NULL
                REFERENCES journeys(id) ON DELETE CASCADE,
              seq INTEGER NOT NULL,
              lat REAL NOT NULL, lon REAL NOT NULL,
              alt REAL, acc REAL NOT NULL, t INTEGER NOT NULL,
              PRIMARY KEY(journey_id, seq))''');
          final b = db.batch();
          for (var i = 0; i < defaultCategories.length; i++) {
            final (name, color) = defaultCategories[i];
            b.insert('categories', {'name': name, 'color': color, 'sort': i});
          }
          await b.commit(noResult: true);
        },
      ),
    );
    return JourneyRepo._(db);
  }

  Future<void> close() => _db.close();

  Future<List<Category>> categories() async => [
        for (final r in await _db.query('categories', orderBy: 'sort, id'))
          Category(r['id'] as int, r['name'] as String, r['color'] as int),
      ];

  Future<int> addCategory(String name, int color) async {
    final max = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT MAX(sort) FROM categories')) ??
        0;
    return _db.insert(
        'categories', {'name': name, 'color': color, 'sort': max + 1});
  }

  Future<void> setCategoryColor(int id, int color) =>
      _db.update('categories', {'color': color},
          where: 'id = ?', whereArgs: [id]);

  Future<void> renameCategory(int id, String name) =>
      _db.update('categories', {'name': name.trim()},
          where: 'id = ?', whereArgs: [id]);

  Future<int> journeyCount(int categoryId) async =>
      Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM journeys WHERE category_id = ?',
          [categoryId])) ??
      0;

  /// Deletes a category; its journeys move to [moveTo]. At least one
  /// category must remain.
  Future<void> deleteCategory(int id, {required int moveTo}) async {
    final n = Sqflite.firstIntValue(
            await _db.rawQuery('SELECT COUNT(*) FROM categories')) ??
        0;
    if (n <= 1 || moveTo == id) {
      throw StateError('Keep at least one category.');
    }
    await _db.transaction((tx) async {
      await tx.update('journeys', {'category_id': moveTo},
          where: 'category_id = ?', whereArgs: [id]);
      await tx.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> save({
    required String name,
    required int categoryId,
    required List<TrackPoint> points,
  }) async {
    if (points.length < 2) {
      throw ArgumentError('A journey needs at least 2 points.');
    }
    final elev = elevationStats(points);
    var minLat = points.first.lat, maxLat = minLat;
    var minLon = points.first.lon, maxLon = minLon;
    for (final p in points) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    return _db.transaction((tx) async {
      final id = await tx.insert('journeys', {
        'name': name.trim().isEmpty ? 'Journey' : name.trim(),
        'category_id': categoryId,
        'started_at': points.first.time.millisecondsSinceEpoch,
        'ended_at': points.last.time.millisecondsSinceEpoch,
        'distance_m': trailDistance(points),
        'duration_s': points.last.time.difference(points.first.time).inSeconds,
        'gain_m': elev.gainM,
        'loss_m': elev.lossM,
        'max_alt_m': elev.maxM,
        'min_alt_m': elev.minM,
        'min_lat': minLat,
        'min_lon': minLon,
        'max_lat': maxLat,
        'max_lon': maxLon,
      });
      final b = tx.batch();
      for (var i = 0; i < points.length; i++) {
        final p = points[i];
        b.insert('points', {
          'journey_id': id,
          'seq': i,
          'lat': p.lat,
          'lon': p.lon,
          'alt': p.altitudeM,
          'acc': p.accuracyM,
          't': p.time.millisecondsSinceEpoch,
        });
      }
      await b.commit(noResult: true);
      return id;
    });
  }

  Future<Journey?> journey(int id) async {
    final r = await _db.query('journeys', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : Journey._from(r.first);
  }

  Future<List<Journey>> list({
    Set<int>? categoryIds,
    String? query,
    JourneySort sort = JourneySort.newest,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (categoryIds != null && categoryIds.isNotEmpty) {
      where.add('category_id IN (${List.filled(categoryIds.length, '?').join(',')})');
      args.addAll(categoryIds);
    }
    final q = query?.trim();
    if (q != null && q.isNotEmpty) {
      where.add('name LIKE ? COLLATE NOCASE');
      args.add('%$q%');
    }
    final rows = await _db.query(
      'journeys',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: switch (sort) {
        JourneySort.newest => 'started_at DESC',
        JourneySort.distance => 'distance_m DESC',
        JourneySort.gain => 'gain_m DESC',
      },
    );
    return rows.map(Journey._from).toList();
  }

  Future<List<TrackPoint>> points(int journeyId) async => [
        for (final r in await _db.query('points',
            where: 'journey_id = ?', whereArgs: [journeyId], orderBy: 'seq'))
          TrackPoint(
            lat: r['lat'] as double,
            lon: r['lon'] as double,
            altitudeM: (r['alt'] as num?)?.toDouble(),
            accuracyM: (r['acc'] as num).toDouble(),
            time: DateTime.fromMillisecondsSinceEpoch(r['t'] as int, isUtc: true),
          ),
      ];

  Future<void> rename(int id, String name) => _db.update(
      'journeys', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);

  Future<void> setCategory(int id, int categoryId) => _db.update(
      'journeys', {'category_id': categoryId},
      where: 'id = ?', whereArgs: [id]);

  Future<void> delete(int id) =>
      _db.delete('journeys', where: 'id = ?', whereArgs: [id]);
}
