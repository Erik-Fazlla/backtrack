import 'dart:io';

import 'package:backtrack/services/offline_maps.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bt_maps'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('empty folder: no regions, no map', () async {
    final m = OfflineMaps(Directory('${dir.path}/maps'));
    await m.scan();
    expect(m.regions, isEmpty);
    await m.useFor(37.98, 23.73);
    expect(m.active, isNull);
    expect(m.provider, isNull);
  });

  test('rejects a file that is not .pmtiles', () async {
    final m = OfflineMaps(Directory('${dir.path}/maps'));
    expect(
      () => m.import('photo.jpg', Stream.value([1, 2, 3])),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects and removes a corrupt .pmtiles file', () async {
    final maps = Directory('${dir.path}/maps');
    final m = OfflineMaps(maps);
    await expectLater(
      m.import('broken.pmtiles', Stream.value(List.filled(200, 7))),
      throwsA(isA<FormatException>()),
    );
    expect(File('${maps.path}/broken.pmtiles').existsSync(), isFalse);
    expect(m.regions, isEmpty);
  });

  test('scan ignores junk files in the maps folder', () async {
    final maps = Directory('${dir.path}/maps')..createSync();
    File('${maps.path}/junk.pmtiles').writeAsBytesSync(List.filled(50, 1));
    File('${maps.path}/notes.txt').writeAsStringSync('hi');
    final m = OfflineMaps(maps);
    await m.scan();
    expect(m.regions, isEmpty);
  });
}
