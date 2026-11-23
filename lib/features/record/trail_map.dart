import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';

import '../../core/geo.dart';
import '../../services/app_settings.dart';
import '../map/base_map.dart';

/// Real map with the trail drawn on top.
///
/// Map: an offline region file (.pmtiles, OpenStreetMap data) when one is
/// downloaded — works with no signal at all. Without one, falls back to
/// online OpenStreetMap tiles. The trail, start and "you are here" are
/// drawn by us, so they always show even when no map loads.
class TrailMap extends StatefulWidget {
  const TrailMap({
    super.key,
    required this.points,
    required this.current,
    required this.recording,
    this.showTiles = true,
    this.offlineTiles,
    this.offlineMaxZoom = 15,
    this.style = MapStyle.light,
  });

  /// Offline map for the current region, or null.
  final PmTilesVectorTileProvider? offlineTiles;
  final int offlineMaxZoom;
  final MapStyle style;

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

class _TrailMapState extends State<TrailMap>
    with SingleTickerProviderStateMixin {
  final _map = MapController();
  bool _ready = false;

  // Smooth motion: GPS gives one fix per second. Between fixes we move the
  // dot along the GPS heading at the GPS speed (display only, never saved),
  // so it glides instead of jumping 1-2 m every second.
  late final Ticker _ticker = createTicker(_onTick);
  TrackPoint? _shownFix;
  DateTime _fixArrivedAt = DateTime.now();
  TrackPoint? _display;
  Duration _lastFrame = Duration.zero;

  void _onTick(Duration elapsed) {
    if (elapsed - _lastFrame < const Duration(milliseconds: 50)) return;
    _lastFrame = elapsed;
    final fix = widget.current;
    if (fix == null || !widget.recording) return;
    final d = extrapolate(fix, DateTime.now().difference(_fixArrivedAt));
    if (_display != null &&
        d.lat == _display!.lat &&
        d.lon == _display!.lon) {
      return; // standing still: no repaint
    }
    setState(() => _display = d);
    if (_ready && _follow) _map.move(_ll(d), _map.camera.zoom);
  }

  void _syncTicker() {
    if (widget.recording && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.recording && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _shownFix = widget.current;
    _display = widget.current;
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// True while the camera follows the blue dot. Turns off when the
  /// user pans; the "locate" button turns it back on.
  bool _follow = true;

  static const _athens = LatLng(37.9838, 23.7275);

  LatLng _ll(TrackPoint p) => LatLng(p.lat, p.lon);

  @override
  void didUpdateWidget(TrailMap old) {
    super.didUpdateWidget(old);
    if (!identical(widget.current, _shownFix)) {
      _shownFix = widget.current;
      _fixArrivedAt = DateTime.now();
      _display = widget.current;
    }
    _syncTicker();
    if (!_ready) return;
    if (old.recording && !widget.recording) {
      _fitTrail();
    } else if (widget.recording && _follow && _display != null) {
      _map.move(_ll(_display!), _map.camera.zoom);
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
    final me = widget.recording ? (_display ?? widget.current) : widget.current;
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
            maxZoom: maxMapZoom,
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
            ...baseMapLayers(
              offlineTiles: widget.offlineTiles,
              style: widget.style,
              showTiles: widget.showTiles,
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
            if (widget.showTiles || widget.offlineTiles != null)
              mapAttribution(),
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
