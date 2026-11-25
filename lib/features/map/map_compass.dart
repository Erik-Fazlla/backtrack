import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../services/heading_service.dart';

/// Compass button for a rotatable map.
/// - Hidden while the map faces north (unless turn-with-me is available).
/// - Red needle shows where north is; tap -> map turns back to north-up.
/// - If [turnWithMeEnabled] (user setting): tapping it while north-up
///   switches to "turn with me" (map follows the phone's direction);
///   tapping again returns to north-up.
class MapCompass extends StatefulWidget {
  const MapCompass({
    super.key,
    required this.map,
    required this.heading,
    required this.turnWithMeEnabled,
  });

  final MapController map;
  final HeadingService? heading;
  final bool turnWithMeEnabled;

  @override
  State<MapCompass> createState() => _MapCompassState();
}

class _MapCompassState extends State<MapCompass> {
  StreamSubscription<MapEvent>? _events;
  double _rotation = 0;
  bool _turnWithMe = false;

  @override
  void initState() {
    super.initState();
    // Map may not be ready on the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _events = widget.map.mapEventStream.listen((e) {
        final r = e.camera.rotation;
        if ((r - _rotation).abs() > 0.5) setState(() => _rotation = r);
        // A manual twist ends turn-with-me (our own rotate() calls don't).
        if (_turnWithMe &&
            e is MapEventRotate &&
            e.source != MapEventSource.mapController) {
          setState(() => _turnWithMe = false);
        }
      });
    });
    widget.heading?.addListener(_onHeading);
  }

  @override
  void didUpdateWidget(MapCompass old) {
    super.didUpdateWidget(old);
    if (old.heading != widget.heading) {
      old.heading?.removeListener(_onHeading);
      widget.heading?.addListener(_onHeading);
    }
    if (!widget.turnWithMeEnabled && _turnWithMe) _setTurnWithMe(false);
  }

  @override
  void dispose() {
    _events?.cancel();
    widget.heading?.removeListener(_onHeading);
    super.dispose();
  }

  void _onHeading() {
    final h = widget.heading?.heading;
    if (!_turnWithMe || h == null) return;
    try {
      widget.map.rotate(-h);
    } catch (_) {/* map not ready */}
  }

  void _setTurnWithMe(bool on) {
    setState(() => _turnWithMe = on);
    if (on) {
      _onHeading();
    } else {
      try {
        widget.map.rotate(0);
      } catch (_) {}
    }
  }

  void _tap() {
    if (_turnWithMe) {
      _setTurnWithMe(false);
    } else if (_rotation.abs() % 360 > 0.5) {
      widget.map.rotate(0);
    } else if (widget.turnWithMeEnabled && widget.heading?.heading != null) {
      _setTurnWithMe(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rotated = _rotation.abs() % 360 > 0.5;
    if (!rotated && !_turnWithMe && !widget.turnWithMeEnabled) {
      return const SizedBox.shrink();
    }
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: _turnWithMe
          ? 'Turning with you · tap for north up'
          : rotated
              ? 'Tap to face north'
              : 'Tap to turn the map with you',
      child: Material(
        key: const Key('map_compass'),
        shape: const CircleBorder(),
        color: _turnWithMe ? const Color(0xFFFF6B00) : cs.surface,
        elevation: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _tap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Transform.rotate(
              angle: _rotation * math.pi / 180,
              child: CustomPaint(
                painter: _NeedlePainter(
                    light: _turnWithMe ? Colors.white : cs.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  _NeedlePainter({required this.light});
  final Color light;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    final north = Path()
      ..moveTo(c.dx, c.dy - 15)
      ..lineTo(c.dx - 5, c.dy)
      ..lineTo(c.dx + 5, c.dy)
      ..close();
    final south = Path()
      ..moveTo(c.dx, c.dy + 15)
      ..lineTo(c.dx - 5, c.dy)
      ..lineTo(c.dx + 5, c.dy)
      ..close();
    canvas.drawPath(north, Paint()..color = const Color(0xFFE53935));
    canvas.drawPath(south, Paint()..color = light.withValues(alpha: 0.7));
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => old.light != light;
}
