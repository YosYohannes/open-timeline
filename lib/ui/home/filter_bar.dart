import 'package:flutter/material.dart';

import '../app/store_scope.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import 'filters.dart';

class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.filter});

  final EntryFilter filter;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: filter,
      builder: (context, _) {
        final range = filter.range;
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              // First so it never scrolls out of sight.
              if (filter.active)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    avatar: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Clear'),
                    onPressed: filter.clear,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              _chip(
                icon: Icons.date_range,
                label: range == null
                    ? 'Dates'
                    : range.start == range.end
                    ? formatShortDay(range.start)
                    : '${formatShortDay(range.start)} – ${formatShortDay(range.end)}',
                active: range != null,
                onPressed: () => _pickRange(context),
                onClear: () => filter.range = null,
              ),
              _chip(
                icon: Icons.sell_outlined,
                label: filter.tag == null ? 'Tag' : '#${filter.tag}',
                active: filter.tag != null,
                onPressed: () => _pickTag(context),
                onClear: () => filter.tag = null,
              ),
              _chip(
                icon: Icons.person_outline,
                label: filter.author == null
                    ? 'Author'
                    : _shortAuthor(filter.author!),
                active: filter.author != null,
                onPressed: () => _pickAuthor(context),
                onClear: () => filter.author = null,
              ),
            ],
          ),
        );
      },
    );
  }

  static String _shortAuthor(String a) {
    final at = a.indexOf('@');
    return at > 0 ? a.substring(0, at) : a;
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onPressed,
    required VoidCallback onClear,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InputChip(
        avatar: Icon(icon, size: 18),
        label: Text(label),
        selected: active,
        showCheckmark: false,
        onPressed: onPressed,
        onDeleted: active ? onClear : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Future<void> _pickRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: filter.range,
      saveText: 'Apply',
    );
    if (picked != null) filter.range = picked;
  }

  Future<void> _pickTag(BuildContext context) async {
    final tags = StoreScope.read(context).allTags;
    final res = await _pickFromList(
      context,
      title: 'Filter by tag',
      anyLabel: 'Any tag',
      empty: 'No tags yet',
      options: tags,
      labelOf: (t) => '#$t',
      selected: filter.tag,
      leading: (_) => const Icon(Icons.sell_outlined),
    );
    if (res != null) filter.tag = res.value;
  }

  Future<void> _pickAuthor(BuildContext context) async {
    final authors = StoreScope.read(context).authors;
    final res = await _pickFromList(
      context,
      title: 'Filter by author',
      anyLabel: 'Everyone',
      empty: 'No posts yet',
      options: authors,
      labelOf: (a) => a,
      selected: filter.author,
      leading: (a) => AuthorDot(author: a, size: 14),
    );
    if (res != null) filter.author = res.value;
  }
}

Future<({String? value})?> _pickFromList(
  BuildContext context, {
  required String title,
  required String anyLabel,
  required String empty,
  required List<String> options,
  required String Function(String) labelOf,
  required String? selected,
  Widget Function(String)? leading,
}) {
  return showModalBottomSheet<({String? value})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.clear_all),
                title: Text(anyLabel),
                selected: selected == null,
                onTap: () => Navigator.pop(ctx, (value: null)),
              ),
              if (options.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(empty, style: Theme.of(ctx).textTheme.bodyMedium),
                ),
              for (final o in options)
                ListTile(
                  leading: leading?.call(o),
                  title: Text(labelOf(o)),
                  selected: o == selected,
                  onTap: () => Navigator.pop(ctx, (value: o)),
                ),
            ],
          ),
        ),
      );
    },
  );
}
