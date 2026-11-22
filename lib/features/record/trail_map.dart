import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';

/// Real map with the trail drawn on top.
///
/// Tiles: OpenStreetMap, loaded online and cached on the phone by
/// flutter_map's built-in cache (areas you have viewed keep working for a
/// while without signal). Full offline Greece map comes next (SPEC §9).
/// The trail, start and "you are here" are drawn by us, so they always
/// show even when no tiles load.
class TrailMap extends StatefulWidget {
  const TrailMap({
    super.key,
    required this.points,
    required this.current,
    required this.recording,
    this.showTiles = true,
  });

  final List<TrackPoint> points;
  final TrackPoint? current;
  final bool recording;

  /// False in widget tests (no network).
  final bool showTiles;

  static const trailColor = Color(0xFFFF6B00);
  static const startColor = Color(0xFF2E9E4F);
  static const meColor = Color(0xFF1E6FE8);

  @override
  State<TrailMap> createState() => _TrailMapState();
}

class _TrailMapState extends State<TrailMap> {
  final _map = MapController();
  bool _ready = false;

  /// True while the camera follows the blue dot. Turns off when the
  /// user pans; the "locate" button turns it back on.
  bool _follow = true;

  static const _athens = LatLng(37.9838, 23.7275);

  LatLng _ll(TrackPoint p) => LatLng(p.lat, p.lon);

  @override
  void didUpdateWidget(TrailMap old) {
    super.didUpdateWidget(old);
    if (!_ready) return;
    if (old.recording && !widget.recording) {
      _fitTrail();
    } else if (widget.recording && _follow && widget.current != null) {
      _map.move(_ll(widget.current!), _map.camera.zoom);
    }
  }

  void _fitTrail() {
    final pts = widget.points.map(_ll).toList();
    if (pts.length < 2) {
      if (pts.isNotEmpty) _map.move(pts.first, 18);
      return;
    }
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.all(48),
      maxZoom: 19,
    ));
  }

  void _recenter() {
    setState(() => _follow = true);
    final c = widget.current ??
        (widget.points.isEmpty ? null : widget.points.last);
    if (c != null) _map.move(_ll(c), _map.camera.zoom < 16 ? 17 : _map.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points.map(_ll).toList();
    final me = widget.current;
    // Draw the live tail from the last saved point to the blue dot so the
    // line keeps up with you between saved points.
    final line = [
      ...pts,
      if (widget.recording && me != null && pts.isNotEmpty) _ll(me),
    ];
    final start = pts.isNotEmpty ? pts.first : null;
    final initial = me != null
        ? _ll(me)
        : (start ?? _athens);

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: initial,
            initialZoom: me != null || start != null ? 17 : 12,
            maxZoom: 19,
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _ready = true;
              if (!widget.recording && pts.length > 1) _fitTrail();
            },
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            if (widget.showTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.erikfazlla.backtrack',
                maxNativeZoom: 19,
              ),
            if (me != null && widget.recording)
              CircleLayer(circles: [
                CircleMarker(
                  point: _ll(me),
                  radius: me.accuracyM,
                  useRadiusInMeter: true,
                  color: TrailMap.meColor.withValues(alpha: 0.15),
                  borderColor: TrailMap.meColor.withValues(alpha: 0.4),
                  borderStrokeWidth: 1,
                ),
              ]),
            if (line.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                  points: line,
                  color: Colors.white,
                  strokeWidth: 8,
                ),
                Polyline(
                  points: line,
                  color: TrailMap.trailColor,
                  strokeWidth: 5,
                ),
              ]),
            MarkerLayer(markers: [
              if (start != null)
                Marker(
                  point: start,
                  width: 22,
                  height: 22,
                  child: const _Dot(color: TrailMap.startColor),
                ),
              if (me != null && widget.recording)
                Marker(
                  point: _ll(me),
                  width: 22,
                  height: 22,
                  child: const _Dot(color: TrailMap.meColor),
                ),
            ]),
            if (widget.showTiles)
              const RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
          ],
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'locate',
            onPressed: widget.recording ? _recenter : _fitTrail,
            tooltip: widget.recording ? 'Follow me' : 'Show whole trail',
            child: Icon(widget.recording
                ? (_follow ? Icons.my_location : Icons.location_searching)
                : Icons.fit_screen),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
      );
}
