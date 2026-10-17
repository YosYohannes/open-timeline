import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import 'cover_theme.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.booklet, this.compact = false});

  final Booklet booklet;
  final bool compact;

  static String _month(DateTime d) => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ][d.month - 1];

  String get _span {
    final a = '${_month(booklet.first)} ${booklet.first.year}';
    final z = '${_month(booklet.last)} ${booklet.last.year}';
    return a == z ? a : '$a – $z';
  }

  @override
  Widget build(BuildContext context) {
    final theme = coverThemeFor(booklet.country);
    final count = booklet.count;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final s = (w / 340).clamp(0.5, 1.2);
        final bandWidth = w * 0.16;
        final small = TextStyle(
          color: theme.ink.withValues(alpha: 0.85),
          fontSize: 12 * s,
          letterSpacing: 0.6,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.paper,
            borderRadius: BorderRadius.horizontal(
              left: Radius.circular(compact ? 3 : 0),
              right: const Radius.circular(5),
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: bandWidth,
                child: Column(
                  children: [
                    for (final c in theme.band)
                      Expanded(
                        child: SizedBox.expand(child: ColoredBox(color: c)),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: bandWidth,
                top: 0,
                bottom: 0,
                width: 8 * s,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withValues(alpha: 0.09),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                left: bandWidth,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24 * s, 30 * s, 16 * s, 24 * s),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booklet.name.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.ink,
                          fontSize: 22 * s,
                          letterSpacing: 3 * s,
                          height: 1.2,
                          fontFamily: 'serif',
                        ),
                      ),
                      SizedBox(height: 10 * s),
                      Container(
                        width: 34 * s,
                        height: 1.5,
                        color: theme.ink.withValues(alpha: 0.6),
                      ),
                      const Spacer(),
                      Text(
                        '$count ${count == 1 ? 'stamp' : 'stamps'}',
                        style: small,
                      ),
                      Text('${booklet.sections.length} series', style: small),
                      if (!compact) ...[
                        SizedBox(height: 4 * s),
                        Text(_span, style: small.copyWith(fontSize: 11 * s)),
                        SizedBox(height: 18 * s),
                        Text(
                          'Swipe to turn the page',
                          style: small.copyWith(
                            fontSize: 10 * s,
                            color: theme.ink.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
