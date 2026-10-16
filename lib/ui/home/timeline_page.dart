import 'package:flutter/material.dart';

import '../../models/entry.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../widgets/author.dart';
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
        if (!filter.active) {
          final past = _onThisDay(all);
          if (past.isNotEmpty) items.add(_OnThisDay(past));
        }
        DateTime? lastDay;
        for (final e in visible) {
          final day = dayOf(e.wallTime);
          if (lastDay != day) {
            items.add(day);
            lastDay = day;
          }
          items.add(e);
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            if (item is _OnThisDay) return _OnThisDayRow(entries: item.entries);
            if (item is DateTime) return _DayHeader(day: item);
            return EntryCard(entry: item as Entry);
          },
        );
      },
    );
  }

  static List<Entry> _onThisDay(List<Entry> all) {
    final now = DateTime.now();
    final list =
        all
            .where(
              (e) =>
                  e.wallTime.month == now.month &&
                  e.wallTime.day == now.day &&
                  e.wallTime.year < now.year,
            )
            .toList()
          ..sort((a, b) => b.wallTime.compareTo(a.wallTime));
    return list;
  }
}

class _OnThisDay {
  _OnThisDay(this.entries);
  final List<Entry> entries;
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

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final theme = Theme.of(context);
    final place = placeText(entry);
    final text = entry.text.trim();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
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
                  const SizedBox(width: 8),
                  AuthorDot(author: entry.author),
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
                  if (entry.starred)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.star_rounded,
                        size: 22,
                        color: Color(0xFFF2B01E),
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
              if (text.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(text, maxLines: 6, overflow: TextOverflow.ellipsis),
              ],
              if (entry.media.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: entry.media.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => MediaTile(
                      file: store.mediaFile(entry, entry.media[i]),
                      name: entry.media[i],
                    ),
                  ),
                ),
              ],
              if (entry.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _OnThisDayRow extends StatelessWidget {
  const _OnThisDayRow({required this.entries});

  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreScope.read(context);
    final nowYear = DateTime.now().year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Icon(Icons.history, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                'On this day',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final e = entries[i];
              final years = nowYear - e.wallTime.year;
              final firstImage = e.media
                  .where((m) => isImage(m) || isVideo(m))
                  .firstOrNull;
              return SizedBox(
                width: 250,
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 0,
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.55,
                  ),
                  child: InkWell(
                    onTap: () => openEntry(context, e.id),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  years == 1
                                      ? '1 year ago'
                                      : '$years years ago',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: theme.colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Expanded(
                                  child: Text(
                                    e.text.trim().isEmpty
                                        ? (placeText(e) ?? '(no text)')
                                        : e.text.trim(),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (firstImage != null) ...[
                            const SizedBox(width: 8),
                            MediaTile(
                              file: store.mediaFile(e, firstImage),
                              name: firstImage,
                              size: 72,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
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
