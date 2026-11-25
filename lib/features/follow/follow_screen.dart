import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:vibration/vibration.dart';

import '../../app_services.dart';
import '../../core/geo.dart';
import '../../core/kalman.dart';
import '../../core/point_filter.dart';
import '../../core/trail_guide.dart';
import '../../services/app_settings.dart';
import '../../services/display_trail.dart';
import '../journeys/format.dart';
import '../map/base_map.dart';
import '../map/heading_beam.dart';
import '../map/map_compass.dart';

/// Follow a trail back to its start (or on to its end): your live position
/// on the trail, an arrow along the path, distance left, progress, and a
/// vibration when you drift off the trail. Works fully offline.
class FollowScreen extends StatefulWidget {
  const FollowScreen({
    super.key,
    required this.services,
    required this.trail,
    required this.title,
    this.color = const Color(0xFFFF6B00),
    this.towardStart = true,
    this.positions,
  });

  final AppServices services;
  final List<TrackPoint> trail;
  final String title;
  final Color color;
  final bool towardStart;

  /// Override the GPS stream (tests).
  final Stream<TrackPoint> Function()? positions;

  @override
  State<FollowScreen> createState() => _FollowScreenState();
}

class _FollowScreenState extends State<FollowScreen> {
  late final TrailGuide _guide = TrailGuide(widget.trail);
  final _monitor = OffTrailMonitor();
  final _filter = PointFilter();
  final _smoother = PositionSmoother();
  final _map = MapController();
  StreamSubscription<TrackPoint>? _sub;

  late bool _towardStart = widget.towardStart;
  TrackPoint? _me;
  TrailPosition? _pos;
  bool _offTrail = false;
  bool _follow = true;
  bool _arrived = false;

  /// Drawn line (snapped when that setting is on). Guidance always uses
  /// the recorded trail.
  late List<TrackPoint> _shown = widget.trail;

  @override
  void initState() {
    super.initState();
    displayTrail(widget.services, widget.trail).then((s) {
      if (mounted) setState(() => _shown = s);
    });
    final src =
        widget.positions ??
        () =>
            widget.services.location?.positions() ??
            const Stream<TrackPoint>.empty();
    _sub = src().listen(_onFix);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _onFix(TrackPoint raw) {
    if (!_filter.accept(raw)) return;
    final me = _smoother.update(raw);
    final pos = _guide.locate(me);
    final wasOff = _offTrail;
    final off = _monitor.update(pos.offTrailM, DateTime.now());
    if (off && !wasOff) _buzz(long: true);
    if (!off && wasOff) _buzz(long: false);
    final target = _towardStart ? widget.trail.first : widget.trail.last;
    final arrived =
        distanceBetween(me, target) < 15 &&
        _guide.remainingM(pos, towardStart: _towardStart) < 25;
    if (arrived && !_arrived) _buzz(long: false);
    setState(() {
      _me = me;
      _pos = pos;
      _offTrail = off;
      _arrived = arrived;
    });
    if (_follow) {
      _map.move(toLatLng(me), math.max(_map.camera.zoom, 16));
    }
  }

  Future<void> _buzz({required bool long}) async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: long ? [0, 600, 200, 600] : [0, 150]);
      }
    } catch (_) {
      // no vibrator: banner still shows
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.services.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([?settings, ?widget.services.heading]),
      builder: (context, _) => _layout(context),
    );
  }

  Widget _panel() => _GuidancePanel(
    guide: _guide,
    me: _me,
    pos: _pos,
    towardStart: _towardStart,
    arrived: _arrived,
    compassDeg: widget.services.heading?.heading,
    onFlip: (v) => setState(() {
      _towardStart = v;
      _arrived = false;
    }),
  );

  Widget _layout(BuildContext context) {
    final settings = widget.services.settings;
    final full = settings?.fullMap ?? false;
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final toggle = settings == null
        ? const SizedBox.shrink()
        : Material(
            color: cs.surface.withValues(alpha: 0.92),
            shape: const CircleBorder(),
            elevation: 3,
            child: IconButton(
              tooltip: full ? 'Exit full screen' : 'Full-screen map',
              icon: Icon(full ? Icons.close_fullscreen : Icons.open_in_full),
              onPressed: () => settings.setFullMap(!full),
            ),
          );
    if (!full) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _mapArea(context, topInset: 12)),
                  Positioned(
                    right: 12,
                    top: _offTrail ? 84 : 12,
                    child: toggle,
                  ),
                ],
              ),
            ),
            _panel(),
          ],
        ),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: _mapArea(context, topInset: top + 8)),
          Positioned(
            left: 8,
            top: top + 4,
            child: Material(
              color: cs.surface.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              elevation: 3,
              child: const BackButton(),
            ),
          ),
          Positioned(right: 12, top: top + (_offTrail ? 80 : 8), child: toggle),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: cs.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              elevation: 4,
              clipBehavior: Clip.antiAlias,
              child: _panel(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapArea(BuildContext context, {required double topInset}) {
    final maps = widget.services.maps;
    final settings = widget.services.settings;
    final trail = _shown.map(toLatLng).toList();
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        ListenableBuilder(
          listenable: Listenable.merge([?maps, ?settings]),
          builder: (context, _) => FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(trail),
                padding: const EdgeInsets.all(48),
                maxZoom: 18,
              ),
              maxZoom: maxMapZoom,
              backgroundColor: cs.surfaceContainerLow,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _follow) {
                  setState(() => _follow = false);
                }
              },
            ),
            children: [
              ...baseMapLayers(
                offlineTiles: maps?.provider,
                style: settings?.mapStyle ?? MapStyle.light,
                showTiles: widget.services.showTiles,
              ),
              PolylineLayer(
                polylines: [
                  Polyline(points: trail, color: Colors.white, strokeWidth: 9),
                  Polyline(points: trail, color: widget.color, strokeWidth: 6),
                ],
              ),
              if (_me != null && widget.services.heading?.heading != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: toLatLng(_me!),
                      width: 140,
                      height: 140,
                      child: HeadingBeam(
                        headingDeg: widget.services.heading!.heading!,
                        accuracyDeg: widget.services.heading!.accuracyDeg,
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: trail.first,
                    width: 26,
                    height: 26,
                    child: const MapDot(
                      color: Color(0xFF2E9E4F),
                      icon: Icons.flag,
                    ),
                  ),
                  Marker(
                    point: trail.last,
                    width: 26,
                    height: 26,
                    child: const MapDot(
                      color: Color(0xFF34495E),
                      icon: Icons.sports_score,
                    ),
                  ),
                  if (_me != null)
                    Marker(
                      point: toLatLng(_me!),
                      width: 22,
                      height: 22,
                      child: const MapDot(color: Color(0xFF1E6FE8)),
                    ),
                ],
              ),
              if (widget.services.showTiles || maps?.provider != null)
                mapAttribution(),
            ],
          ),
        ),
        if (_offTrail)
          Positioned(
            left: 12,
            right: 12,
            top: topInset,
            child: Material(
              key: const Key('off_trail_banner'),
              color: cs.error,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'Off trail: ${_pos!.offTrailM.toStringAsFixed(0)} m '
                  'away. Follow the arrow back to the line.',
                  style: TextStyle(
                    color: cs.onError,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          top: topInset + (_offTrail ? 72 : 0) + 56,
          child: MapCompass(
            map: _map,
            heading: widget.services.heading,
            turnWithMeEnabled: settings?.turnWithMe ?? false,
          ),
        ),
        Positioned(
          right: 12,
          bottom: (settings?.fullMap ?? false) ? 220 : 12,
          child: FloatingActionButton.small(
            heroTag: 'follow_me',
            onPressed: () {
              setState(() => _follow = true);
              if (_me != null) _map.move(toLatLng(_me!), 17);
            },
            child: Icon(_follow ? Icons.my_location : Icons.location_searching),
          ),
        ),
      ],
    );
  }
}

class _GuidancePanel extends StatelessWidget {
  const _GuidancePanel({
    required this.guide,
    required this.me,
    required this.pos,
    required this.towardStart,
    required this.arrived,
    required this.onFlip,
    this.compassDeg,
  });

  /// Where the top of the phone points (compass), if available.
  final double? compassDeg;

  final TrailGuide guide;
  final TrackPoint? me;
  final TrailPosition? pos;
  final bool towardStart;
  final bool arrived;
  final ValueChanged<bool> onFlip;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final me = this.me, pos = this.pos;

    Widget body;
    if (me == null || pos == null) {
      body = const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Waiting for GPS…', textAlign: TextAlign.center),
      );
    } else if (arrived) {
      body = Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          towardStart ? 'You are back at the start.' : 'You reached the end.',
          key: const Key('arrived'),
          style: t.titleLarge,
          textAlign: TextAlign.center,
        ),
      );
    } else {
      final aim = guide.aimPoint(pos, towardStart: towardStart);
      final bearing = bearingDeg(me, aim);
      final moving = (me.speedMps ?? 0) >= 0.5 && me.headingDeg != null;
      // Best: compass = where you face, works standing still. Else GPS
      // walking direction. Else plain compass bearing (north up).
      final facing = compassDeg ?? (moving ? me.headingDeg : null);
      final angle = facing != null ? relativeAngle(bearing, facing) : bearing;
      final remaining = guide.remainingM(pos, towardStart: towardStart);
      final target = towardStart ? guide.trail.first : guide.trail.last;
      final straight = distanceBetween(me, target);
      final pct = towardStart ? 1 - pos.progress : pos.progress;
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(
          children: [
            Transform.rotate(
              angle: angle * math.pi / 180,
              child: const Icon(
                Icons.navigation,
                key: Key('guide_arrow'),
                size: 64,
                color: Color(0xFF1E6FE8),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatDistance(remaining)} along the trail',
                    key: const Key('remaining'),
                    style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatDistance(straight)} straight line · '
                    '${compassDeg != null
                        ? 'arrow = turn this way'
                        : moving
                        ? 'arrow = your walking direction'
                        : 'arrow = compass, north up'}',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: pct.clamp(0, 1).toDouble(),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(pct * 100).clamp(0, 100).toStringAsFixed(0)}% of the way '
                    '${towardStart ? 'back' : 'to the end'}',
                    style: t.labelSmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.flag),
                  label: Text('To start'),
                ),
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.sports_score),
                  label: Text('To end'),
                ),
              ],
              selected: {towardStart},
              onSelectionChanged: (v) => onFlip(v.first),
            ),
          ),
        ],
      ),
    );
  }
}
