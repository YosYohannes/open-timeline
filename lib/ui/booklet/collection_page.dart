import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import '../app/store_scope.dart';
import 'book_cover.dart';
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
      padding: const EdgeInsets.fromLTRB(16, 16, 20, 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: kBookRatio,
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
    final code = booklet.country;
    return InkWell(
      key: ValueKey('booklet-${code ?? 'none'}'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BookletPage(country: code)),
      ),
      child: BookCover(booklet: booklet, compact: true),
    );
  }
}
