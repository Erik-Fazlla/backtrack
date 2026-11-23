import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pmtiles/pmtiles.dart';
import 'package:vector_tile/vector_tile.dart';

import '../core/geo.dart';
import '../core/path_matcher.dart';

/// Reads roads and footpaths (Protomaps `roads` layer) from an offline
/// .pmtiles map for the area around a trail. Fully offline.
class PathSource {
  PathSource(this.archive);
  final PmTilesArchive archive;

  static Future<PathSource> open(String path) async =>
      PathSource(await PmTilesArchive.from(path));

  Future<void> close() => archive.close();

  /// Lines inside the trail's bounding box plus [marginM].
  /// Uses the file's most detailed zoom, stepping down if the area would
  /// need more than [maxTiles] tiles.
  Future<List<PathLine>> around(List<TrackPoint> trail,
      {double marginM = 40, int maxTiles = 64}) async {
    if (trail.isEmpty) return const [];
    var minLat = trail.first.lat, maxLat = minLat;
    var minLon = trail.first.lon, maxLon = minLon;
    for (final p in trail) {
      minLat = math.min(minLat, p.lat);
      maxLat = math.max(maxLat, p.lat);
      minLon = math.min(minLon, p.lon);
      maxLon = math.max(maxLon, p.lon);
    }
    final dLat = marginM / 111195.0;
    final dLon = marginM / (111195.0 * math.cos(minLat * math.pi / 180));
    minLat -= dLat;
    maxLat += dLat;
    minLon -= dLon;
    maxLon += dLon;

    var z = archive.maxZoom;
    late int x0, x1, y0, y1;
    while (true) {
      (x0, y0) = _tileXY(maxLat, minLon, z);
      (x1, y1) = _tileXY(minLat, maxLon, z);
      if ((x1 - x0 + 1) * (y1 - y0 + 1) <= maxTiles || z <= archive.minZoom) {
        break;
      }
      z--;
    }

    final out = <PathLine>[];
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        List<int> bytes;
        try {
          bytes = (await archive.tile(ZXY(z, x, y).toTileId())).bytes();
        } catch (_) {
          continue; // no tile here (sea, outside region)
        }
        if (bytes.isEmpty) continue;
        final tile = VectorTile.fromBytes(bytes: Uint8List.fromList(bytes));
        for (final layer in tile.layers) {
          if (layer.name != 'roads') continue;
          final extent = layer.extent;
          for (final f in layer.features) {
            final g = f.decodeGeometry();
            final parts = switch (g) {
              GeometryLineString(:final coordinates) => [coordinates],
              GeometryMultiLineString(:final coordinates) => coordinates,
              _ => const <List<List<double>>>[],
            };
            for (final part in parts) {
              if (part.length < 2) continue;
              out.add(PathLine([
                for (final c in part) _toLatLon(z, x, y, extent, c[0], c[1]),
              ]));
            }
          }
        }
      }
    }
    return out;
  }

  static (int, int) _tileXY(double lat, double lon, int z) {
    final n = 1 << z;
    final x = ((lon + 180) / 360 * n).floor().clamp(0, n - 1);
    final r = lat * math.pi / 180;
    final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
        .floor()
        .clamp(0, n - 1);
    return (x, y);
  }

  static (double, double) _toLatLon(
      int z, int tx, int ty, int extent, double px, double py) {
    final n = (1 << z).toDouble();
    final lon = (tx + px / extent) / n * 360 - 180;
    final yy = (ty + py / extent) / n;
    final lat =
        math.atan(_sinh(math.pi * (1 - 2 * yy))) * 180 / math.pi;
    return (lat, lon);
  }

  static double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;
}
