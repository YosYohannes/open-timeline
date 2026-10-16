import 'package:flutter/material.dart';

import '../app/store_scope.dart';
import '../widgets/author.dart';
import '../widgets/format.dart';
import 'filters.dart';

bool hasSheetFilters(EntryFilter f) =>
    f.range != null || f.tag != null || f.author != null;

Future<void> showFilterSheet(BuildContext context, EntryFilter filter) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _FilterSheet(filter: filter),
  );
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.filter});

  final EntryFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: filter,
        builder: (context, _) {
          final range = filter.range;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Filters',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (hasSheetFilters(filter))
                      TextButton(
                        onPressed: () {
                          filter.range = null;
                          filter.tag = null;
                          filter.author = null;
                        },
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ),
              _row(
                icon: Icons.date_range,
                title: 'Dates',
                value: range == null
                    ? null
                    : range.start == range.end
                    ? formatShortDay(range.start)
                    : '${formatShortDay(range.start)} – ${formatShortDay(range.end)}',
                empty: 'Any date',
                onTap: () => _pickRange(context),
                onClear: () => filter.range = null,
              ),
              _row(
                icon: Icons.sell_outlined,
                title: 'Tag',
                value: filter.tag == null ? null : '#${filter.tag}',
                empty: 'Any tag',
                onTap: () => _pickTag(context),
                onClear: () => filter.tag = null,
              ),
              _row(
                icon: Icons.person_outline,
                title: 'Author',
                value: filter.author,
                empty: 'Everyone',
                onTap: () => _pickAuthor(context),
                onClear: () => filter.author = null,
              ),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required String title,
    required String? value,
    required String empty,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value ?? empty),
      selected: value != null,
      trailing: value == null
          ? const Icon(Icons.chevron_right)
          : IconButton(
              tooltip: 'Clear $title',
              icon: const Icon(Icons.close),
              onPressed: onClear,
            ),
      onTap: onTap,
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
