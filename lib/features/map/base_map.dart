import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../../core/geo.dart';
import '../../services/app_settings.dart';

/// Highest zoom any map in the app shows. Offline files hold z15 detail and
/// are over-zoomed beyond that.
const double maxMapZoom = 19;

// Building a map theme parses a big style; do it once per style.
// V4 = Protomaps basemap v4, the format of current daily builds.
final _themes = <MapStyle, vtr.Theme>{};
vtr.Theme _themeFor(MapStyle s) => _themes.putIfAbsent(
    s,
    () => s == MapStyle.dark
        ? ProtomapsThemes.darkV4()
        : ProtomapsThemes.lightV4());

/// The background map: offline region when available (works with no
/// signal), else online OpenStreetMap tiles, else nothing (tests).
List<Widget> baseMapLayers({
  required PmTilesVectorTileProvider? offlineTiles,
  required MapStyle style,
  bool showTiles = true,
}) =>
    [
      if (offlineTiles != null)
        VectorTileLayer(
          // Key includes the style: a style change must rebuild the layer,
          // or already-drawn tiles keep the old look until restart.
          key: ValueKey((offlineTiles, style)),
          tileProviders: TileProviders({'protomaps': offlineTiles}),
          theme: _themeFor(style),
          maximumZoom: maxMapZoom,
          // Draw vectors directly. The default raster mode renders tiles to
          // images and showed nothing on the test phone (Xiaomi, Mali GPU,
          // Impeller) with no error.
          layerMode: VectorTileLayerMode.vector,
        )
      else if (showTiles)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.erikfazlla.backtrack',
          maxNativeZoom: 19,
        ),
    ];

Widget mapAttribution() => const RichAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      attributions: [
        TextSourceAttribution('OpenStreetMap contributors'),
        TextSourceAttribution('Protomaps'),
      ],
    );

LatLng toLatLng(TrackPoint p) => LatLng(p.lat, p.lon);

/// White-edged round dot used for start / end / you-are-here markers.
class MapDot extends StatelessWidget {
  const MapDot({super.key, required this.color, this.icon});
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: icon == null
            ? null
            : Icon(icon, size: 14, color: Colors.white),
      );
}
