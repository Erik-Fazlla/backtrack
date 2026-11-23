import 'package:flutter/material.dart';

import '../../services/journey_repo.dart';
import 'format.dart';

/// Result of the save sheet.
class SaveChoice {
  const SaveChoice(this.name, this.categoryId);
  final String name;
  final int categoryId;
}

/// Bottom sheet: name the journey and pick a category.
Future<SaveChoice?> showSaveJourneySheet(
  BuildContext context, {
  required List<Category> categories,
  required String defaultName,
  int? initialCategoryId,
  String title = 'Save journey',
  String action = 'Save',
}) =>
    showModalBottomSheet<SaveChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _SaveSheet(
        categories: categories,
        defaultName: defaultName,
        initialCategoryId: initialCategoryId,
        title: title,
        action: action,
      ),
    );

class _SaveSheet extends StatefulWidget {
  const _SaveSheet({
    required this.categories,
    required this.defaultName,
    required this.initialCategoryId,
    required this.title,
    required this.action,
  });
  final List<Category> categories;
  final String defaultName;
  final int? initialCategoryId;
  final String title;
  final String action;

  @override
  State<_SaveSheet> createState() => _SaveSheetState();
}

class _SaveSheetState extends State<_SaveSheet> {
  late final _name = TextEditingController(text: widget.defaultName);
  late int _cat = widget.initialCategoryId ??
      widget.categories
          .firstWhere((c) => c.name == 'Walk', orElse: () => widget.categories.first)
          .id;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() =>
      Navigator.pop(context, SaveChoice(_name.text.trim(), _cat));

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            key: const Key('journey_name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 16),
          Text('Category', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in widget.categories)
                ChoiceChip(
                  key: Key('cat_${c.name}'),
                  avatar: CircleAvatar(backgroundColor: colorOf(c.color)),
                  label: Text(c.name),
                  selected: _cat == c.id,
                  onSelected: (_) => setState(() => _cat = c.id),
                ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              key: const Key('save_journey_confirm'),
              onPressed: _save,
              child: Text(widget.action),
            ),
          ),
        ],
      ),
    );
  }
}
