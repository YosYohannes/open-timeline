import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import '../../models/countries.dart';
import '../app/store_scope.dart';
import '../app/theme.dart';
import 'booklet_page.dart';

class CollectionPage extends StatelessWidget {
  const CollectionPage({super.key});

  @override
  Widget build(BuildContext context) {
    final booklets = StoreScope.of(context).booklets;
    final theme = Theme.of(context);
    if (booklets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.collections_bookmark_outlined,
                size: 72,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('No stamps yet', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Tap the button to scan your first stamp. Each country gets its own booklet.',
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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: booklets.length,
      itemBuilder: (context, i) => _Cover(booklet: booklets[i]),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.booklet});

  final Booklet booklet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = booklet.country;
    return Material(
      color: const Color(0xFF1B1A18),
      shape: RoundedRectangleBorder(
        borderRadius: kBorderRadius,
        side: const BorderSide(color: Color(0xFF3A372F)),
      ),
      child: InkWell(
        key: ValueKey('booklet-${code ?? 'none'}'),
        customBorder: RoundedRectangleBorder(borderRadius: kBorderRadius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => BookletPage(country: code)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                code == null ? '📖' : countryFlag(code),
                style: const TextStyle(fontSize: 52),
              ),
              const SizedBox(height: 12),
              Text(
                booklet.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFFE9DFC8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${booklet.count} ${booklet.count == 1 ? 'stamp' : 'stamps'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB9AE95),
                ),
              ),
              Text(
                '${booklet.sections.length} series',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8E846E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
