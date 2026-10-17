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
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF211E1A), Color(0xFF141210)],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final gap = 22.0;
          final bookWidth = ((box.maxWidth - 32 - gap) / 2).floorToDouble();
          final rows = <List<Booklet>>[
            for (var i = 0; i < booklets.length; i += 2)
              booklets.sublist(i, i + 2 > booklets.length ? i + 1 : i + 2),
          ];
          return ListView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 96),
            itemCount: rows.length,
            itemBuilder: (context, i) =>
                _ShelfRow(booklets: rows[i], bookWidth: bookWidth, gap: gap),
          );
        },
      ),
    );
  }
}

const _headroom = 30.0;
const _surface = 26.0;
const _lip = 14.0;

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.booklets,
    required this.bookWidth,
    required this.gap,
  });

  final List<Booklet> booklets;
  final double bookWidth;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final bookHeight = bookWidth / kBookRatio;
    return SizedBox(
      height: _headroom + bookHeight + _surface * 0.55 + _lip,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _surface + _lip,
            child: const _Ledge(),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: _lip + _surface * 0.45,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < booklets.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  _Standing(
                    booklet: booklets[i],
                    width: bookWidth,
                    height: bookHeight,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ledge extends StatelessWidget {
  const _Ledge();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF5E4C3B), Color(0xFF8A735C)],
              ),
            ),
            child: SizedBox.expand(),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF4A3B2D), Color(0xFF2B2119)],
            ),
            border: const Border(top: BorderSide(color: Color(0xFF7A644E))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: const SizedBox(height: _lip, width: double.infinity),
        ),
      ],
    );
  }
}

class _Standing extends StatelessWidget {
  const _Standing({
    required this.booklet,
    required this.width,
    required this.height,
  });

  final Booklet booklet;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final code = booklet.country;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 8,
            top: 6,
            width: width,
            height: height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 14,
                    spreadRadius: -2,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 2,
            right: -6,
            bottom: -4,
            height: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: InkWell(
              key: ValueKey('booklet-${code ?? 'none'}'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BookletPage(country: code),
                ),
              ),
              child: BookCover(booklet: booklet, compact: true),
            ),
          ),
        ],
      ),
    );
  }
}
