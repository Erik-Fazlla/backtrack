import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../services/journey_repo.dart';
import 'category_editor.dart';
import 'format.dart';
import 'journey_detail_screen.dart';

/// All saved journeys as a list: search, filter by category, sort.
/// "+ New" adds a category; long-press a chip to rename, recolour or delete.
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

  Future<void> _addCategory() async {
    final r = await showCategoryEditor(context, all: _categories);
    if (r == null) return;
    await repo.addCategory(r.$1, r.$2);
    widget.services.notifyJourneysChanged();
  }

  Future<void> _editCategory(Category c) async {
    final r = await showCategoryEditor(context, existing: c, all: _categories);
    if (r == null) return;
    await repo.renameCategory(c.id, r.$1);
    await repo.setCategoryColor(c.id, r.$2);
    widget.services.notifyJourneysChanged();
  }

  Future<void> _deleteCategory(Category c) async {
    final others = _categories.where((o) => o.id != c.id).toList();
    if (others.isEmpty) return;
    final target = others.firstWhere((o) => o.name == 'Other',
        orElse: () => others.first);
    final n = await repo.journeyCount(c.id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: Text(n == 0
            ? 'No journeys use it.'
            : '$n ${n == 1 ? 'journey moves' : 'journeys move'} to '
                '"${target.name}". No journey is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('category_delete_confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await repo.deleteCategory(c.id, moveTo: target.id);
    _cats.remove(c.id);
    widget.services.notifyJourneysChanged();
  }

  Future<void> _manageCategory(Category c) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(backgroundColor: colorOf(c.color)),
              title: Text(c.name,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              key: const Key('category_edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename / colour'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (_categories.length > 1)
              ListTile(
                key: const Key('category_delete'),
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete category'),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (action == 'edit') await _editCategory(c);
    if (action == 'delete') await _deleteCategory(c);
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
                      onLongPress: () => _manageCategory(c),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ActionChip(
                    key: const Key('add_category'),
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                    onPressed: _addCategory,
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
