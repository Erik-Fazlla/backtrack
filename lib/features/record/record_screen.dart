import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/geo.dart';
import '../../services/location_service.dart';
import '../../services/recorder.dart';
import 'trail_map.dart';

/// M0 screen: one big button, live trail on a grid, test stats.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.recorder,
    this.location,
    this.showTiles = true,
  });

  final Recorder recorder;
  final bool showTiles;

  /// Null in widget tests: permissions are skipped.
  final LocationService? location;

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  Recorder get rec => widget.recorder;
  Timer? _ticker;
  bool _batteryOk = true;
  String? _problem;

  @override
  void initState() {
    super.initState();
    rec.addListener(_changed);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (rec.state == RecState.recording) setState(() {});
    });
    _checkBattery();
  }

  Future<void> _checkBattery() async {
    final loc = widget.location;
    if (loc == null) return;
    final ok = await loc.isBatteryOptimizationIgnored();
    if (mounted) setState(() => _batteryOk = ok);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    rec.removeListener(_changed);
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final loc = widget.location;
    if (loc != null) {
      final r = await loc.ensureReady();
      if (r != LocationReadiness.ready) {
        setState(() => _problem = switch (r) {
              LocationReadiness.serviceOff =>
                'Location is turned off. Turn it on to record.',
              LocationReadiness.deniedForever =>
                'Location permission is blocked. Allow it in app settings.',
              _ => 'Backtrack needs location permission to record.',
            });
        return;
      }
    }
    setState(() => _problem = null);
    await rec.start();
  }

  Future<void> _confirmStop() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop recording?'),
        content: const Text('The trail is kept so you can follow it back.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep recording')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Stop')),
        ],
      ),
    );
    if (ok == true) await rec.stop();
  }

  String _duration() {
    final s = rec.startedAt;
    if (s == null || rec.points.isEmpty) return '0:00';
    final end = rec.state == RecState.recording
        ? DateTime.now().toUtc()
        : rec.points.last.time;
    final d = end.difference(s.toUtc());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '${d.inMinutes}:$sec';
  }

  String _km(double m) =>
      m < 1000 ? '${m.toStringAsFixed(0)} m' : '${(m / 1000).toStringAsFixed(2)} km';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pts = rec.points;
    final latest = rec.latest;
    final current = rec.state == RecState.stopped
        ? null
        : latest ?? (pts.isEmpty ? null : pts.last);
    final alt = latest?.altitudeM ?? (pts.isEmpty ? null : pts.last.altitudeM);

    return Scaffold(
      appBar: AppBar(title: const Text('Backtrack'), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            if (!_batteryOk)
              MaterialBanner(
                content: const Text(
                    'Battery optimisation may stop recording when the screen is off.'),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await widget.location?.requestIgnoreBatteryOptimization();
                      await _checkBattery();
                    },
                    child: const Text('Allow'),
                  ),
                ],
              ),
            if (_problem != null)
              MaterialBanner(
                backgroundColor: cs.errorContainer,
                content: Text(_problem!),
                actions: [
                  TextButton(
                    onPressed: () => widget.location?.openAppSettings(),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: TrailMap(
                        key: const Key('trail'),
                        points: pts,
                        current: current,
                        recording: rec.state == RecState.recording ||
                            rec.state == RecState.waitingForFix,
                        showTiles: widget.showTiles,
                      ),
                    ),
                    if (pts.isEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        top: 12,
                        child: Material(
                          color: cs.surface.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              switch (rec.state) {
                                RecState.waitingForFix =>
                                  'Getting an accurate position… '
                                      '${rec.warmupProgress}/${rec.warmupRequired}\n'
                                      'Stand still under open sky.',
                                _ => 'Press Record at your starting point.\nNo signal or internet needed.',
                              },
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (rec.state == RecState.recording && !rec.moving)
              Text('Standing still: trail paused',
                  style: Theme.of(context).textTheme.labelMedium),
            _Stats(items: [
              ('Distance', _km(rec.distanceM)),
              ('Time', _duration()),
              ('Points', '${pts.length}'),
              ('GPS ±', rec.lastAccuracyM == null
                  ? '–'
                  : '${rec.lastAccuracyM!.toStringAsFixed(0)} m'),
              ('Altitude', alt == null ? '–' : '${alt.toStringAsFixed(0)} m'),
              ('Max gap', _km(maxGap(pts))),
            ]),
            if (rec.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('GPS error: ${rec.error}',
                    style: TextStyle(color: cs.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 64,
                child: switch (rec.state) {
                  RecState.idle || RecState.stopped => FilledButton.icon(
                      key: const Key('record'),
                      onPressed: _start,
                      icon: const Icon(Icons.fiber_manual_record),
                      label: Text(rec.state == RecState.stopped
                          ? 'New recording'
                          : 'Record'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B00),
                        textStyle: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                  _ => FilledButton.icon(
                      key: const Key('stop'),
                      onPressed: _confirmStop,
                      icon: const Icon(Icons.stop),
                      label: const Text('Stop'),
                      style: FilledButton.styleFrom(
                        backgroundColor: cs.inverseSurface,
                        textStyle: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        children: [
          for (final (label, value) in items)
            SizedBox(
              width: (MediaQuery.sizeOf(context).width - 24) / 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Text(value,
                        style: t.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text(label, style: t.bodySmall),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
