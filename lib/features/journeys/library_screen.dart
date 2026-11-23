import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../services/journey_repo.dart';
import 'format.dart';
import 'journey_detail_screen.dart';

/// All saved journeys as a list: search, filter by category, sort.
/// Long-press a category chip to change its colour.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  JourneyRepo get repo => widget.services.repo;
  final _search = TextEditingController();
  final Set<int> _cats = {};
  JourneySort _sort = JourneySort.newest;
  List<Category> _categories = const [];
  List<Journey> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.services.journeysChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.services.journeysChanged.removeListener(_load);
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cats = await repo.categories();
    final items = await repo.list(
        categoryIds: _cats, query: _search.text, sort: _sort);
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _items = items;
      _loading = false;
    });
  }

  Future<void> _pickColor(Category c) async {
    final color = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c.name} colour'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final p in categoryPalette)
              InkWell(
                onTap: () => Navigator.pop(ctx, p),
                customBorder: const CircleBorder(),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: colorOf(p),
                  child: p == c.color
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
    if (color == null) return;
    await repo.setCategoryColor(c.id, color);
    widget.services.notifyJourneysChanged();
  }

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in _categories) c.id: c};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          PopupMenuButton<JourneySort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) {
              _sort = s;
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: JourneySort.newest, child: Text('Newest first')),
              PopupMenuItem(value: JourneySort.distance, child: Text('Longest first')),
              PopupMenuItem(value: JourneySort.gain, child: Text('Most climbing')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              key: const Key('library_search'),
              controller: _search,
              onChanged: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _search.clear();
                          _load();
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final c in _categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: GestureDetector(
                      onLongPress: () => _pickColor(c),
                      child: FilterChip(
                        key: Key('filter_${c.name}'),
                        avatar: CircleAvatar(backgroundColor: colorOf(c.color)),
                        label: Text(c.name),
                        selected: _cats.contains(c.id),
                        onSelected: (on) {
                          on ? _cats.add(c.id) : _cats.remove(c.id);
                          _load();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            _search.text.isEmpty && _cats.isEmpty
                                ? 'No saved journeys yet.\nRecord one and tap Save.'
                                : 'Nothing matches.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: _items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final j = _items[i];
                          final c = byId[j.categoryId];
                          return _JourneyCard(
                            journey: j,
                            category: c,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => JourneyDetailScreen(
                                    services: widget.services, journeyId: j.id),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard(
      {required this.journey, required this.category, required this.onTap});
  final Journey journey;
  final Category? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final color = colorOf(category?.color ?? 0xFF7F8C8D);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Container(width: 6, height: 84, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(journey.name,
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text('${category?.name ?? '—'} · ${formatDate(journey.startedAt)}',
                        style: t.bodySmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      children: [
                        _Stat(Icons.straighten, formatDistance(journey.distanceM)),
                        _Stat(Icons.timer_outlined, formatDuration(journey.durationS)),
                        _Stat(Icons.trending_up, '${journey.gainM.toStringAsFixed(0)} m'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelLarge),
        ],
      );
}
