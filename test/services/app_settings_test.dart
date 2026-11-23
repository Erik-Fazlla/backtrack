import 'dart:io';

import 'package:backtrack/services/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bt_settings'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('defaults to satellites-only GPS', () async {
    final s = AppSettings(File('${dir.path}/settings.json'));
    await s.load();
    expect(s.gpsMode, GpsMode.satellites);
  });

  test('gps mode persists across restarts', () async {
    final f = File('${dir.path}/settings.json');
    await AppSettings(f).setGpsMode(GpsMode.fused);
    final again = AppSettings(f);
    await again.load();
    expect(again.gpsMode, GpsMode.fused);
  });

  test('corrupt file falls back to defaults', () async {
    final f = File('${dir.path}/settings.json')..writeAsStringSync('{oops');
    final s = AppSettings(f);
    await s.load();
    expect(s.gpsMode, GpsMode.satellites);
  });
}
