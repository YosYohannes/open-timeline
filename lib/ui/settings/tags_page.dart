import 'package:flutter/material.dart';

import '../../models/tag.dart';
import '../../store/journal_store.dart';
import '../app/store_scope.dart';
import '../widgets/snack.dart';

class TagsPage extends StatelessWidget {
  const TagsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final counts = store.tagCounts;
    final tags = store.allTags;
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: tags.isEmpty
          ? const Center(child: Text('No tags yet'))
          : ListView(
              children: [
                for (final t in tags)
                  ListTile(
                    key: ValueKey('tag-$t'),
                    title: Text('#$t'),
                    subtitle: Text(_posts(counts[t] ?? 0)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Rename or merge',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(context, store, t),
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, store, t),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  static String _posts(int n) => n == 1 ? '1 post' : '$n posts';

  Future<void> _rename(
    BuildContext context,
    JournalStore store,
    String tag,
  ) async {
    final others = store.allTags.where((t) => t != tag).toList();
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(tag: tag, others: others),
    );
    if (next == null || !context.mounted) return;
    final n = await store.changeTag(tag, next);
    if (context.mounted) {
      showSnack(context, '#$tag is now #$next on ${_posts(n)}');
    }
  }

  Future<void> _delete(
    BuildContext context,
    JournalStore store,
    String tag,
  ) async {
    final count = store.tagCounts[tag] ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete #$tag?'),
        content: Text(
          'It is removed from ${_posts(count)}, including posts by other people. '
          'The change goes to everyone on the next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final n = await store.changeTag(tag, null);
    if (context.mounted) showSnack(context, 'Removed #$tag from ${_posts(n)}');
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.tag, required this.others});

  final String tag;
  final List<String> others;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _text = TextEditingController(
    text: widget.tag,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String? get _next {
    final t = normalizeTag(_text.text);
    return t == null || t == widget.tag ? null : t;
  }

  String? get _mergesInto {
    final t = _next?.toLowerCase();
    if (t == null) return null;
    return widget.others.where((o) => o.toLowerCase() == t).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final merge = _mergesInto;
    return AlertDialog(
      title: Text('Rename #${widget.tag}'),
      content: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'New name',
          helperText: merge == null ? null : 'Merges into #$merge',
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          final next = _next;
          if (next != null) Navigator.pop(context, merge ?? next);
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _next == null
              ? null
              : () => Navigator.pop(context, merge ?? _next),
          child: Text(merge == null ? 'Rename' : 'Merge'),
        ),
      ],
    );
  }
}
