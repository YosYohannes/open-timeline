import 'package:flutter/material.dart';

import '../../models/entry.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import '../widgets/format.dart';
import '../widgets/media_tile.dart';

class StampTile extends StatelessWidget {
  const StampTile({super.key, required this.entry});

  final Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreScope.read(context);
    final image = entry.media.where(isImage).firstOrNull;
    final place = placeText(entry);
    final detail = [
      if (entry.series.isNotEmpty) entry.series,
      ?place,
    ].join(' · ');
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
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              if (image != null)
                MediaTile(
                  file: store.mediaFile(entry, image),
                  name: image,
                  size: 64,
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title.isEmpty ? 'Stamp' : entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      formatTime(entry),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.collections_bookmark_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _count(List<Entry> items) {
  final noun = items.every((e) => e.isStamp) ? 'stamp' : 'item';
  return items.length == 1 ? '1 $noun' : '${items.length} ${noun}s';
}

class StampStrip extends StatelessWidget {
  const StampStrip({super.key, required this.stamps});

  final List<Entry> stamps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final store = StoreScope.read(context);
    final names = stamps
        .map((e) => e.title.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final caption = [
      _count(stamps),
      if (names.isNotEmpty)
        names.length > 2
            ? '${names.take(2).join(', ')}, +${names.length - 2}'
            : names.join(', '),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.collections_bookmark_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stamps.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final e = stamps[i];
                  final image = e.media.where(isImage).firstOrNull;
                  return image == null
                      ? const SizedBox(width: 64)
                      : MediaTile(
                          file: store.mediaFile(e, image),
                          name: image,
                          size: 64,
                          onTap: () => openEntry(context, e.id),
                        );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
