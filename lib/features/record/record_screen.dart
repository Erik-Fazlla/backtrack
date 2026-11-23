import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_services.dart';
import '../../core/elevation.dart';
import '../../core/geo.dart';
import '../follow/follow_screen.dart';
import '../journeys/format.dart';
import '../journeys/save_journey_sheet.dart';
import '../../core/map_region.dart';
import '../../services/app_settings.dart';
import '../../services/location_service.dart';
import '../../services/offline_maps.dart';
import '../../services/recorder.dart';
import 'trail_map.dart';

/// M0 screen: one big button, live trail on a grid, test stats.
class RecordScreen extends StatefulWidget {
  const RecordScreen({
    super.key,
    required this.recorder,
    this.location,
    this.settings,
    this.maps,
    this.services,
    this.showTiles = true,
  });

  /// Repo + navigation targets for Save / Take me back (null in old tests).
  final AppServices? services;
  final Recorder recorder;
  final AppSettings? settings;
  final OfflineMaps? maps;
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

  void _changed() {
    final p = rec.latest;
    // Switch to the offline map region you are in (cheap when unchanged).
    if (p != null) widget.maps?.useFor(p.lat, p.lon);
    setState(() {});
  }

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
    setState(() {
      _problem = null;
      _savedId = null;
    });
    await rec.start();
  }

  Future<void> _shareLog() async {
    final files = await rec.store.latestFiles();
    if (files.isEmpty) return;
    await SharePlus.instance.share(ShareParams(
      files: [for (final f in files) XFile(f.path)],
      text: 'Backtrack GPS log',
    ));
  }

  Future<void> _openSettings() async {
    final s = widget.settings!;
    final recording = rec.state == RecState.recording ||
        rec.state == RecState.waitingForFix;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => ListenableBuilder(
        listenable: s,
        builder: (c, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text('GPS mode',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                ),
                if (recording)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Stop recording to change the GPS mode.'),
                  ),
                RadioGroup<GpsMode>(
                  groupValue: s.gpsMode,
                  onChanged: (m) {
                    if (!recording && m != null) s.setGpsMode(m);
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<GpsMode>(
                        value: GpsMode.satellites,
                        enabled: !recording,
                        title: const Text('Satellites only'),
                        subtitle: const Text(
                            'Pure GPS. Same as in a forest with no signal.'),
                      ),
                      RadioListTile<GpsMode>(
                        value: GpsMode.fused,
                        enabled: !recording,
                        title: const Text('Google location'),
                        subtitle: const Text(
                            'GPS + phone motion sensors. Try both on the same walk.'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const _SheetTitle('Map style'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<MapStyle>(
                    segments: const [
                      ButtonSegment(
                          value: MapStyle.light,
                          icon: Icon(Icons.light_mode),
                          label: Text('Light')),
                      ButtonSegment(
                          value: MapStyle.dark,
                          icon: Icon(Icons.dark_mode),
                          label: Text('Dark')),
                    ],
                    selected: {s.mapStyle},
                    onSelectionChanged: (v) => s.setMapStyle(v.first),
                  ),
                ),
                if (widget.maps != null) ...[
                  const Divider(),
                  const _SheetTitle('Offline maps'),
                  _OfflineMapsSection(maps: widget.maps!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Id of the journey saved from the current recording (null = not saved).
  int? _savedId;

  Future<void> _save() async {
    final svc = widget.services;
    if (svc == null || rec.points.length < 2) return;
    final cats = await svc.repo.categories();
    if (!mounted) return;
    final choice = await showSaveJourneySheet(
      context,
      categories: cats,
      defaultName: 'Journey · ${formatDate(rec.points.first.time)}',
    );
    if (choice == null) return;
    final id = await svc.repo.save(
      name: choice.name,
      categoryId: choice.categoryId,
      points: rec.points,
    );
    svc.notifyJourneysChanged();
    if (!mounted) return;
    setState(() => _savedId = id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved "${choice.name.isEmpty ? 'Journey' : choice.name}" to your Library.')),
    );
  }

  void _takeMeBack() {
    final svc = widget.services;
    if (svc == null || rec.points.length < 2) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FollowScreen(
          services: svc,
          trail: rec.points,
          title: 'Back to start',
        ),
      ),
    );
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

  /// "Altitude" label with uphill/downhill over the last 50 m.
  String _slopeLabel() {
    final g = currentGrade(rec.points);
    if (g == null || rec.state != RecState.recording) return 'Altitude';
    return switch (gradeLabel(g)) {
      Slope.uphill => 'Uphill ${g.toStringAsFixed(0)}%',
      Slope.downhill => 'Downhill ${(-g).toStringAsFixed(0)}%',
      Slope.flat => 'Flat',
    };
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
      appBar: AppBar(
        title: const Text('Backtrack'),
        centerTitle: true,
        actions: [
          if (rec.state == RecState.stopped)
            IconButton(
              key: const Key('share_log'),
              tooltip: 'Share GPS log',
              icon: const Icon(Icons.ios_share),
              onPressed: _shareLog,
            ),
          if (widget.settings != null)
            IconButton(
              key: const Key('settings'),
              tooltip: 'GPS mode',
              icon: const Icon(Icons.tune),
              onPressed: _openSettings,
            ),
        ],
      ),
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
                      child: ListenableBuilder(
                        listenable: Listenable.merge([
                          if (widget.maps != null) widget.maps!,
                          if (widget.settings != null) widget.settings!,
                        ]),
                        builder: (context, _) => TrailMap(
                          key: const Key('trail'),
                          points: pts,
                          current: current,
                          recording: rec.state == RecState.recording ||
                              rec.state == RecState.waitingForFix,
                          showTiles: widget.showTiles,
                          offlineTiles: widget.maps?.provider,
                          offlineMaxZoom: widget.maps?.active?.maxZoom ?? 15,
                          style: widget.settings?.mapStyle ?? MapStyle.light,
                        ),
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
              (_slopeLabel(), alt == null ? '–' : '${alt.toStringAsFixed(0)} m'),
              ('Max gap', _km(maxGap(pts))),
            ]),
            if (rec.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('GPS error: ${rec.error}',
                    style: TextStyle(color: cs.error)),
              ),
            if (rec.state == RecState.stopped &&
                pts.length >= 2 &&
                widget.services != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: FilledButton.icon(
                          key: const Key('take_me_back'),
                          onPressed: _takeMeBack,
                          icon: const Icon(Icons.u_turn_left),
                          label: const Text('Take me back'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E6FE8),
                            textStyle: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          key: const Key('save_journey'),
                          onPressed: _savedId == null ? _save : null,
                          icon: Icon(_savedId == null
                              ? Icons.bookmark_add_outlined
                              : Icons.check),
                          label: Text(_savedId == null ? 'Save' : 'Saved'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: rec.state == RecState.stopped &&
                        pts.length >= 2 &&
                        widget.services != null
                    ? 48
                    : 64,
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

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      );
}

/// Lists downloaded map regions; import a .pmtiles file or delete one.
class _OfflineMapsSection extends StatefulWidget {
  const _OfflineMapsSection({required this.maps});
  final OfflineMaps maps;

  @override
  State<_OfflineMapsSection> createState() => _OfflineMapsSectionState();
}

class _OfflineMapsSectionState extends State<_OfflineMapsSection> {
  bool _busy = false;
  String? _message;

  Future<void> _import() async {
    final picked =
        await FilePicker.pickFiles(dialogTitle: 'Pick a .pmtiles map');
    if (picked.isEmpty) return;
    final f = picked.first;
    setState(() {
      _busy = true;
      _message = 'Copying ${f.name}…';
    });
    try {
      final r = await widget.maps.import(f.name, f.readAsByteStream());
      _message = 'Added ${r.name} (${r.sizeLabel}).';
    } on FormatException catch (e) {
      _message = e.message;
    } catch (e) {
      _message = 'Import failed: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirmDelete(MapRegion r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete ${r.name}?'),
        content: Text('Frees ${r.sizeLabel}. You can import it again later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await widget.maps.delete(r);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.maps,
      builder: (context, _) {
        final regions = widget.maps.regions;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (regions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('No offline map yet. Import a .pmtiles file '
                    '(e.g. greece.pmtiles) to see the map with no signal.'),
              ),
            for (final r in regions)
              ListTile(
                leading: Icon(widget.maps.active?.path == r.path
                    ? Icons.map
                    : Icons.map_outlined),
                title: Text(r.name),
                subtitle:
                    Text('${r.sizeLabel} · detail up to zoom ${r.maxZoom}'),
                trailing: IconButton(
                  tooltip: 'Delete map',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _confirmDelete(r),
                ),
              ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(_message!),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download),
                label: const Text('Import map file'),
              ),
            ),
          ],
        );
      },
    );
  }
}
