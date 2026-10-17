import 'package:flutter/material.dart';

import '../../models/booklet.dart';
import 'flag_spine.dart';

class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.booklet, this.compact = false});

  final Booklet booklet;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final count = booklet.count;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final s = (w / 340).clamp(0.5, 1.2);
        final bandWidth = w * 0.16;
        final small = TextStyle(
          color: kCoverInk.withValues(alpha: 0.85),
          fontSize: 12 * s,
          letterSpacing: 0.6,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: kCoverPaper,
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
                child: FlagSpine(country: booklet.country),
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
                          color: kCoverInk,
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
                        color: kCoverInk.withValues(alpha: 0.6),
                      ),
                      const Spacer(),
                      Text(
                        '$count ${count == 1 ? 'stamp' : 'stamps'}',
                        style: small,
                      ),
                      Text('${booklet.sections.length} series', style: small),
                      if (!compact) ...[
                        SizedBox(height: 18 * s),
                        Text(
                          'Swipe to turn the page',
                          style: small.copyWith(
                            fontSize: 10 * s,
                            color: kCoverInk.withValues(alpha: 0.5),
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
