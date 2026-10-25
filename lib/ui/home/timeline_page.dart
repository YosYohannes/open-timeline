import 'package:flutter/material.dart';

import '../../models/entry.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import '../stamp/stamp_widgets.dart';
import '../widgets/format.dart';
import '../widgets/media_tile.dart';
import 'filters.dart';

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key, required this.filter});

  final EntryFilter filter;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: filter,
      builder: (context, _) {
        final all = store.entries;
        if (all.isEmpty) return const _EmptyState();

        final visible = filter.apply(all)
          ..sort((a, b) => b.wallTime.compareTo(a.wallTime));
        if (visible.isEmpty) return _NoMatches(filter: filter);

        final items = <Object>[];
        final byDay = <DateTime, List<Entry>>{};
        for (final e in visible) {
          byDay.putIfAbsent(dayOf(e.wallTime), () => []).add(e);
        }
        for (final d in byDay.entries) {
          items.add(d.key);
          final stamps = d.value
              .where((e) => e.isCollectible)
              .toList()
              .reversed;
          if (stamps.isNotEmpty) items.add(StampStrip(stamps: stamps.toList()));
          items.addAll(d.value.where((e) => !e.isCollectible));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item is DateTime) return _DayHeader(day: item);
            if (item is StampStrip) return item;
            return EntryCard(entry: item as Entry);
          },
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        formatDayHeader(day),
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _thumbSize = 96.0;

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    if (entry.isCollectible) return StampTile(entry: entry);
    final theme = Theme.of(context);
    final place = placeText(entry);
    final text = entry.text.trim();
    final hasMedia = entry.media.isNotEmpty;
    final textLines = !hasMedia ? 6 : (entry.tags.isEmpty ? 4 : 3);

    final body = [
      if (text.isNotEmpty)
        Text(text, maxLines: textLines, overflow: TextOverflow.ellipsis),
      if (entry.tags.isNotEmpty) ...[
        if (text.isNotEmpty) const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: -6,
          children: [
            for (final t in entry.tags)
              Chip(
                label: Text('#$t'),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelStyle: theme.textTheme.labelSmall,
                padding: EdgeInsets.zero,
                side: BorderSide.none,
                backgroundColor: theme.colorScheme.secondaryContainer
                    .withValues(alpha: 0.6),
              ),
          ],
        ),
      ],
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => openEntry(context, entry.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    formatTime(entry),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.title.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (entry.conflict)
                    Tooltip(
                      message: 'Conflicting edits were merged - please review',
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
              if (place != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.place_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        place,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (body.isNotEmpty || hasMedia) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (body.isNotEmpty)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: body,
                        ),
                      ),
                    if (hasMedia && body.isNotEmpty) const SizedBox(width: 10),
                    if (hasMedia) _Thumbnail(entry: entry),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final more = entry.media.length - 1;
    return SizedBox(
      width: _thumbSize,
      height: _thumbSize,
      child: Stack(
        children: [
          MediaTile(
            file: store.mediaFile(entry, entry.media.first),
            name: entry.media.first,
            size: _thumbSize,
          ),
          if (more > 0)
            Positioned(
              right: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: kBorderRadius,
                ),
                child: Text(
                  '+$more',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No posts yet', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Tap the + button to write your first post.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.filter});

  final EntryFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'No posts match the filters',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: filter.clear,
              child: const Text('Clear filters'),
            ),
          ],
        ),
      ),
    );
  }
}
