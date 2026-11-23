/// An offline map file covering a rectangle of the world (e.g. Greece).
class MapRegion {
  const MapRegion({
    required this.name,
    required this.path,
    required this.minLat,
    required this.minLon,
    required this.maxLat,
    required this.maxLon,
    required this.maxZoom,
    required this.sizeBytes,
  });

  final String name;
  final String path;
  final double minLat;
  final double minLon;
  final double maxLat;
  final double maxLon;
  final int maxZoom;
  final int sizeBytes;

  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  double get areaDeg2 => (maxLat - minLat) * (maxLon - minLon);

  String get sizeLabel {
    final mb = sizeBytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.toStringAsFixed(0)} MB';
  }
}

/// Which downloaded map to show at a position: the smallest region that
/// contains it (most detailed, e.g. Attica over Greece). With no position
/// yet, or outside all regions, falls back to the largest one so the user
/// still sees a map.
MapRegion? pickRegion(List<MapRegion> regions, double? lat, double? lon) {
  if (regions.isEmpty) return null;
  if (lat != null && lon != null) {
    final inside = regions.where((r) => r.contains(lat, lon)).toList()
      ..sort((a, b) => a.areaDeg2.compareTo(b.areaDeg2));
    if (inside.isNotEmpty) return inside.first;
  }
  final all = [...regions]..sort((a, b) => b.areaDeg2.compareTo(a.areaDeg2));
  return all.first;
}
