import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../app_services.dart';
import '../../core/elevation.dart';
import '../../core/geo.dart';
import '../../services/app_settings.dart';
import '../../services/journey_repo.dart';
import '../follow/follow_screen.dart';
import '../map/base_map.dart';
import 'elevation_chart.dart';
import 'format.dart';
import 'save_journey_sheet.dart';

/// One saved journey: its line on the map, stats, elevation profile,
/// and Follow / rename / change category / delete.
class JourneyDetailScreen extends StatefulWidget {
  const JourneyDetailScreen(
      {super.key, required this.services, required this.journeyId});
  final AppServices services;
  final int journeyId;

  @override
  State<JourneyDetailScreen> createState() => _JourneyDetailScreenState();
}

class _JourneyDetailScreenState extends State<JourneyDetailScreen> {
  JourneyRepo get repo => widget.services.repo;
  Journey? _j;
  Category? _cat;
  List<Category> _cats = const [];
  List<TrackPoint> _pts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final j = await repo.journey(widget.journeyId);
    final cats = await repo.categories();
    final pts = await repo.points(widget.journeyId);
    if (!mounted) return;
    setState(() {
      _j = j;
      _cats = cats;
      _cat = cats.where((c) => c.id == j?.categoryId).firstOrNull;
      _pts = pts;
    });
  }

  Future<void> _edit() async {
    final j = _j!;
    final r = await showSaveJourneySheet(
      context,
      categories: _cats,
      defaultName: j.name,
      initialCategoryId: j.categoryId,
      title: 'Edit journey',
      action: 'Save changes',
    );
    if (r == null) return;
    if (r.name.isNotEmpty && r.name != j.name) await repo.rename(j.id, r.name);
    if (r.categoryId != j.categoryId) await repo.setCategory(j.id, r.categoryId);
    widget.services.notifyJourneysChanged();
    await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${_j!.name}"?'),
        content: const Text('The trail is removed from this phone. '
            'This cannot be undone.'),
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
    if (ok != true) return;
    await repo.delete(_j!.id);
    widget.services.notifyJourneysChanged();
    if (mounted) Navigator.pop(context);
  }

  void _follow(bool towardStart) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FollowScreen(
            services: widget.services,
            trail: _pts,
            title: _j!.name,
            color: colorOf(_cat?.color ?? 0xFFFF6B00),
            towardStart: towardStart,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final j = _j;
    if (j == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }
    final color = colorOf(_cat?.color ?? 0xFFFF6B00);
    final t = Theme.of(context).textTheme;
    final maps = widget.services.maps;
    final settings = widget.services.settings;
    final line = _pts.map(toLatLng).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(j.name),
        actions: [
          IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _edit),
          IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SizedBox(
            height: 280,
            child: line.length < 2
                ? const SizedBox()
                : ListenableBuilder(
                    listenable: Listenable.merge([?maps, ?settings]),
                    builder: (context, _) => FlutterMap(
                      options: MapOptions(
                        initialCameraFit: CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(line),
                          padding: const EdgeInsets.all(32),
                          maxZoom: 18,
                        ),
                        maxZoom: maxMapZoom,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerLow,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                        ),
                      ),
                      children: [
                        ...baseMapLayers(
                          offlineTiles: maps?.provider,
                          style: settings?.mapStyle ?? MapStyle.light,
                          showTiles: widget.services.showTiles,
                        ),
                        PolylineLayer(polylines: [
                          Polyline(
                              points: line, color: Colors.white, strokeWidth: 8),
                          Polyline(points: line, color: color, strokeWidth: 5),
                        ]),
                        MarkerLayer(markers: [
                          Marker(
                            point: line.first,
                            width: 24,
                            height: 24,
                            child: const MapDot(
                                color: Color(0xFF2E9E4F), icon: Icons.flag),
                          ),
                          Marker(
                            point: line.last,
                            width: 24,
                            height: 24,
                            child: const MapDot(
                                color: Color(0xFF34495E),
                                icon: Icons.sports_score),
                          ),
                        ]),
                      ],
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                CircleAvatar(radius: 6, backgroundColor: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                      '${_cat?.name ?? '—'} · ${formatDate(j.startedAt)}',
                      style: t.bodyMedium,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              children: [
                _Tile('Distance', formatDistance(j.distanceM)),
                _Tile('Time', formatDuration(j.durationS)),
                _Tile('Climb', '+${j.gainM.toStringAsFixed(0)} m'),
                _Tile('Descent', '−${j.lossM.toStringAsFixed(0)} m'),
                _Tile('Highest',
                    j.maxAltM == null ? '–' : '${j.maxAltM!.toStringAsFixed(0)} m'),
                _Tile('Lowest',
                    j.minAltM == null ? '–' : '${j.minAltM!.toStringAsFixed(0)} m'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text('Elevation', style: t.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
            child: ElevationChart(profile: elevationProfile(_pts), color: color),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('follow_start'),
                    onPressed: _pts.length < 2 ? null : () => _follow(true),
                    icon: const Icon(Icons.flag),
                    label: const Text('Follow to start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pts.length < 2 ? null : () => _follow(false),
                    icon: const Icon(Icons.sports_score),
                    label: const Text('Follow to end'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: (MediaQuery.sizeOf(context).width - 16) / 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(value,
                style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            Text(label, style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
