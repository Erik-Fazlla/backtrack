import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../app_services.dart';
import '../../services/app_settings.dart';
import '../../services/journey_repo.dart';
import '../map/base_map.dart';
import '../map/map_compass.dart';
import 'format.dart';
import 'journey_detail_screen.dart';

/// Every saved journey drawn on one map in its category colour.
/// Tap a line for its name and stats.
class JourneysMapScreen extends StatefulWidget {
  const JourneysMapScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<JourneysMapScreen> createState() => _JourneysMapScreenState();
}

class _Track {
  _Track(this.journey, this.points);
  final Journey journey;
  final List<LatLng> points;
}

class _JourneysMapScreenState extends State<JourneysMapScreen> {
  JourneyRepo get repo => widget.services.repo;
  final _map = MapController();
  final _hit = LayerHitNotifier<int>(null);
  final Set<int> _cats = {};
  List<Category> _categories = const [];
  List<_Track> _tracks = const [];
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    widget.services.journeysChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.services.journeysChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final cats = await repo.categories();
    final js = await repo.list(categoryIds: _cats);
    final tracks = <_Track>[];
    for (final j in js) {
      final pts = await repo.points(j.id);
      // Thin out long trails: plenty for drawing many lines at once.
      final step = (pts.length / 400).ceil().clamp(1, 1 << 30);
      tracks.add(_Track(j, [
        for (var i = 0; i < pts.length; i += step) toLatLng(pts[i]),
        if (pts.isNotEmpty && (pts.length - 1) % step != 0) toLatLng(pts.last),
      ]));
    }
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _tracks = tracks;
    });
    if (!_fitted) _fitAll();
  }

  void _fitAll() {
    final all = [for (final t in _tracks) ...t.points];
    if (all.length < 2) return;
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(all),
        padding: const EdgeInsets.all(40),
        maxZoom: 17,
      ));
      _fitted = true;
    } catch (_) {
      // map not ready yet; onMapReady retries
    }
  }

  void _onTap() {
    final hit = _hit.value;
    if (hit == null || hit.hitValues.isEmpty) return;
    final ids = hit.hitValues.toSet().toList();
    final tracks = [
      for (final id in ids) _tracks.firstWhere((t) => t.journey.id == id)
    ];
    final byId = {for (final c in _categories) c.id: c};
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tracks.length > 1)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('Several journeys here'),
              ),
            for (final t in tracks)
              ListTile(
                key: Key('map_journey_${t.journey.id}'),
                leading: CircleAvatar(
                    backgroundColor:
                        colorOf(byId[t.journey.categoryId]?.color ?? 0xFF7F8C8D)),
                title: Text(t.journey.name),
                subtitle: Text(
                  '${byId[t.journey.categoryId]?.name ?? ''} · '
                  '${formatDate(t.journey.startedAt)}\n'
                  '${formatDistance(t.journey.distanceM)} · '
                  '${formatDuration(t.journey.durationS)} · '
                  '+${t.journey.gainM.toStringAsFixed(0)} m',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(c);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JourneyDetailScreen(
                          services: widget.services, journeyId: t.journey.id),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maps = widget.services.maps;
    final settings = widget.services.settings;
    final byId = {for (final c in _categories) c.id: c};
    return Scaffold(
      appBar: AppBar(title: const Text('Map')),
      body: Stack(
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([?maps, ?settings]),
            builder: (context, _) => FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(37.9838, 23.7275),
                initialZoom: 12,
                maxZoom: maxMapZoom,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerLow,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onMapReady: _fitAll,
              ),
              children: [
                ...baseMapLayers(
                  offlineTiles: maps?.provider,
                  style: settings?.mapStyle ?? MapStyle.light,
                  showTiles: widget.services.showTiles,
                ),
                GestureDetector(
                  onTap: _onTap,
                  child: PolylineLayer<int>(
                    hitNotifier: _hit,
                    minimumHitbox: 16,
                    polylines: [
                      for (final t in _tracks) ...[
                        Polyline<int>(
                          points: t.points,
                          color: Colors.white,
                          strokeWidth: 7,
                          hitValue: t.journey.id,
                        ),
                        Polyline<int>(
                          points: t.points,
                          color: colorOf(
                              byId[t.journey.categoryId]?.color ?? 0xFFFF6B00),
                          strokeWidth: 4,
                          hitValue: t.journey.id,
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.services.showTiles || maps?.provider != null)
                  mapAttribution(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final c in _categories)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        avatar: CircleAvatar(backgroundColor: colorOf(c.color)),
                        label: Text(c.name),
                        selected: _cats.contains(c.id),
                        onSelected: (on) {
                          on ? _cats.add(c.id) : _cats.remove(c.id);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_tracks.isEmpty)
            const Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Saved journeys will appear here.'),
                ),
              ),
            ),
          Positioned(
            right: 12,
            top: 60,
            child: MapCompass(
              map: _map,
              heading: widget.services.heading,
              turnWithMeEnabled: false,
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: FloatingActionButton.small(
              heroTag: 'fit_all',
              tooltip: 'Show all',
              onPressed: _fitAll,
              child: const Icon(Icons.fit_screen),
            ),
          ),
        ],
      ),
    );
  }
}
