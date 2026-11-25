import 'dart:io';

import 'package:backtrack/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bt_settings'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('map style persists across restarts', () async {
    final f = File('${dir.path}/settings.json');
    await AppSettings(f).setMapStyle(MapStyle.dark);
    final again = AppSettings(f);
    await again.load();
    expect(again.mapStyle, MapStyle.dark);
  });

  test('snap to paths defaults off and persists', () async {
    final f = File('${dir.path}/settings.json');
    final s = AppSettings(f);
    await s.load();
    expect(s.snapToPaths, isFalse);
    await s.setSnapToPaths(true);
    final again = AppSettings(f);
    await again.load();
    expect(again.snapToPaths, isTrue);
  });

  test('turn-with-me and full map persist (default off)', () async {
    final f = File('${dir.path}/settings.json');
    final s = AppSettings(f);
    await s.load();
    expect(s.turnWithMe, isFalse);
    expect(s.fullMap, isFalse);
    await s.setTurnWithMe(true);
    await s.setFullMap(true);
    final again = AppSettings(f);
    await again.load();
    expect(again.turnWithMe, isTrue);
    expect(again.fullMap, isTrue);
  });

  test('corrupt file falls back to defaults', () async {
    final f = File('${dir.path}/settings.json')..writeAsStringSync('{oops');
    final s = AppSettings(f);
    await s.load();
    expect(s.mapStyle, MapStyle.light);
    expect(s.snapToPaths, isFalse);
  });
}
