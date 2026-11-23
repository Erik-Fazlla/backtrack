import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../core/map_region.dart';

/// Offline map regions stored on the phone as .pmtiles files
/// (Protomaps / OpenStreetMap vector data). Works with no internet.
///
/// Files live in `<app files>/maps/`. They get there by:
///  - Settings -> Offline maps -> Import (file picker), or
///  - copying with Android Studio Device Explorer into
///    Android/data/com.erikfazlla.backtrack/files/maps/
class OfflineMaps extends ChangeNotifier {
  OfflineMaps(this.dir);

  final Directory dir;

  List<MapRegion> _regions = const [];
  List<MapRegion> get regions => _regions;

  MapRegion? _active;
  MapRegion? get active => _active;

  PmTilesVectorTileProvider? _provider;
  /// Tile provider for [active], ready to render. Null = no offline map.
  PmTilesVectorTileProvider? get provider => _provider;

  String? _error;
  String? get error => _error;

  Future<void> scan() async {
    await dir.create(recursive: true);
    final found = <MapRegion>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.toLowerCase().endsWith('.pmtiles')) continue;
      final r = await _read(f);
      if (r != null) found.add(r);
    }
    found.sort((a, b) => a.name.compareTo(b.name));
    _regions = found;
    if (_active != null && !found.any((r) => r.path == _active!.path)) {
      _active = null;
      _provider = null;
    }
    notifyListeners();
  }

  Future<MapRegion?> _read(File f) async {
    PmTilesArchive? a;
    try {
      a = await PmTilesArchive.from(f.path);
      final name = f.uri.pathSegments.last.replaceAll(
          RegExp(r'\.pmtiles$', caseSensitive: false), '');
      return MapRegion(
        name: name,
        path: f.path,
        minLat: a.minPosition.latitude,
        minLon: a.minPosition.longitude,
        maxLat: a.maxPosition.latitude,
        maxLon: a.maxPosition.longitude,
        maxZoom: a.maxZoom,
        sizeBytes: await f.length(),
      );
    } catch (e) {
      debugPrint('Not a valid map file ${f.path}: $e');
      return null;
    } finally {
      await a?.close();
    }
  }

  /// Show the best region for this position (loads it if needed).
  Future<void> useFor(double? lat, double? lon) async {
    final pick = pickRegion(_regions, lat, lon);
    if (pick?.path == _active?.path && (_provider != null || pick == null)) {
      return;
    }
    _active = pick;
    _provider = null;
    _error = null;
    notifyListeners();
    if (pick == null) return;
    try {
      _provider = await PmTilesVectorTileProvider.fromSource(pick.path);
    } catch (e) {
      _error = 'Could not open map ${pick.name}: $e';
    }
    notifyListeners();
  }

  /// Copy a picked .pmtiles file into the maps folder and check it opens.
  /// Streams the bytes (map files are hundreds of MB; Android pickers give
  /// content:// URIs, not paths). Returns the new region or throws a
  /// readable [FormatException].
  Future<MapRegion> import(String name, Stream<List<int>> bytes) async {
    await dir.create(recursive: true);
    if (!name.toLowerCase().endsWith('.pmtiles')) {
      throw const FormatException('Pick a .pmtiles map file.');
    }
    final dest = File('${dir.path}/$name');
    final sink = dest.openWrite();
    try {
      await sink.addStream(bytes);
    } finally {
      await sink.close();
    }
    final r = await _read(dest);
    if (r == null) {
      await dest.delete();
      throw const FormatException('That file is not a readable map.');
    }
    await scan();
    return r;
  }

  Future<void> delete(MapRegion r) async {
    if (_active?.path == r.path) {
      _active = null;
      _provider = null;
    }
    final f = File(r.path);
    if (await f.exists()) await f.delete();
    await scan();
  }
}
