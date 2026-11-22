import 'dart:io';

import 'package:backtrack/core/geo.dart';
import 'package:backtrack/services/track_store.dart';
import 'package:flutter_test/flutter_test.dart';

TrackPoint p(double lat, int sec) => TrackPoint(
      lat: lat,
      lon: 23.73,
      accuracyM: 5,
      time: DateTime.utc(2026, 1, 1).add(Duration(seconds: sec)),
    );

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('bt_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('no sessions -> loadLatest is null', () async {
    expect(await TrackStore(dir).loadLatest(), isNull);
  });

  test('appended points survive a "crash" (new store instance)', () async {
    final s = TrackStore(dir);
    await s.startSession(DateTime.utc(2026, 1, 1));
    await s.append(p(37.98, 0));
    await s.append(p(37.981, 5));
    // no finish() -> simulates the app being killed

    final loaded = await TrackStore(dir).loadLatest();
    expect(loaded, isNotNull);
    expect(loaded!.points.length, 2);
    expect(loaded.finished, isFalse);
    expect(loaded.points.last.lat, 37.981);
  });

  test('finish marks the session as finished', () async {
    final s = TrackStore(dir);
    await s.startSession(DateTime.utc(2026, 1, 1));
    await s.append(p(37.98, 0));
    await s.finish();

    final loaded = await TrackStore(dir).loadLatest();
    expect(loaded!.finished, isTrue);
    expect(loaded.points.length, 1);
  });

  test('latest session wins and a torn last line is ignored', () async {
    final s = TrackStore(dir);
    await s.startSession(DateTime.utc(2026, 1, 1));
    await s.append(p(1, 0));
    await s.finish();
    await s.startSession(DateTime.utc(2026, 1, 2));
    await s.append(p(2, 0));
    // simulate a half-written line from a kill mid-write
    final f = dir.listSync().whereType<File>().firstWhere(
        (f) => f.path.contains('20260102'));
    f.writeAsStringSync('{"lat": 3, "lo', mode: FileMode.append);

    final loaded = await TrackStore(dir).loadLatest();
    expect(loaded!.points.single.lat, 2);
  });
}
