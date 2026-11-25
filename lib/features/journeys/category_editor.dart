import 'package:flutter/material.dart';

import '../../services/journey_repo.dart';
import 'format.dart';

/// Name + colour dialog for a new or existing category.
/// Returns null when cancelled.
Future<(String, int)?> showCategoryEditor(
  BuildContext context, {
  Category? existing,
  required List<Category> all,
}) =>
    showDialog<(String, int)>(
      context: context,
      builder: (_) => _CategoryEditor(existing: existing, all: all),
    );

class _CategoryEditor extends StatefulWidget {
  const _CategoryEditor({required this.existing, required this.all});
  final Category? existing;
  final List<Category> all;

  @override
  State<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.color ?? _unusedColor();

  int _unusedColor() {
    final used = {for (final c in widget.all) c.color};
    return categoryPalette.firstWhere((p) => !used.contains(p),
        orElse: () => categoryPalette.first);
  }

  String? get _error {
    final n = _name.text.trim();
    if (n.isEmpty) return null;
    final clash = widget.all.any((c) =>
        c.id != widget.existing?.id && c.name.toLowerCase() == n.toLowerCase());
    return clash ? 'Already exists' : null;
  }

  bool get _valid => _name.text.trim().isNotEmpty && _error == null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'New category' : 'Edit category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('category_name'),
              controller: _name,
              autofocus: widget.existing == null,
              maxLength: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _error,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final p in categoryPalette)
                  InkWell(
                    onTap: () => setState(() => _color = p),
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: colorOf(p),
                      child: p == _color
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('category_save'),
            onPressed: _valid
                ? () => Navigator.pop(context, (_name.text.trim(), _color))
                : null,
            child: const Text('Save'),
          ),
        ],
      );
}
