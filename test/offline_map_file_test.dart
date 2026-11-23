import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:backtrack/services/offline_maps.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pmtiles/pmtiles.dart';

/// Checks a real downloaded offline map (maps/greece.pmtiles, git-ignored).
/// Skipped when the file isn't on this PC.
ZXY tileAt(double lat, double lon, int z) {
  final n = 1 << z;
  final x = ((lon + 180) / 360 * n).floor();
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
      .floor();
  return ZXY(z, x, y);
}

void main() {
  final file = File('maps/greece.pmtiles');

  test('greece.pmtiles is a valid offline map with real detail', () async {
    final a = await PmTilesArchive.from(file.path);
    addTearDown(a.close);

    // Covers Greece, full detail.
    expect(a.minPosition.latitude, lessThan(35.0));
    expect(a.maxPosition.latitude, greaterThan(41.5));
    expect(a.minPosition.longitude, lessThan(20.0));
    expect(a.maxPosition.longitude, greaterThan(29.0));
    expect(a.maxZoom, 15);

    // Real vector data where you'd use it: city, nearby mountain, Olympus.
    final places = {
      'Athens centre': (37.9838, 23.7275),
      'Mt Parnitha': (38.1700, 23.7200),
      'Mt Olympus': (40.0850, 22.3580),
    };
    for (final e in places.entries) {
      final t = await a.tile(tileAt(e.value.$1, e.value.$2, 15).toTileId());
      final bytes = t.bytes();
      expect(bytes, isNotEmpty, reason: '${e.key}: no tile');
      // Layer names are stored as plain strings inside the vector tile.
      final text = latin1.decode(bytes, allowInvalid: true);
      expect(text.contains('roads') || text.contains('earth'), isTrue,
          reason: '${e.key}: tile has no map layers');
      // ignore: avoid_print
      print('${e.key}: z15 tile ${bytes.length} bytes, '
          'roads=${text.contains('roads')} landuse=${text.contains('landuse')}');
    }
  }, skip: !file.existsSync() ? 'maps/greece.pmtiles not downloaded' : false);

  test('app picks it up like on the phone', () async {
    final m = OfflineMaps(Directory('maps'));
    await m.scan();
    final g = m.regions.singleWhere((r) => r.name == 'greece');
    expect(g.maxZoom, 15);
    await m.useFor(37.9838, 23.7275);
    expect(m.active?.name, 'greece');
    expect(m.provider, isNotNull);
    expect(m.error, isNull);
  }, skip: !file.existsSync() ? 'maps/greece.pmtiles not downloaded' : false);
}
