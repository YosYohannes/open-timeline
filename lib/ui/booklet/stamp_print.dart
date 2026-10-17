import 'package:flutter/material.dart';

import '../../models/entry.dart';
import '../app/navigation.dart';
import '../app/store_scope.dart';
import 'collage_layout.dart';
import 'stamp_image.dart';

const kInkBrown = Color(0xFF6B624F);

class StampPrint extends StatelessWidget {
  const StampPrint({super.key, required this.entry, required this.placed});

  final Entry entry;
  final Placed placed;

  String get _date =>
      '${entry.wallTime.day} ${_month(entry.wallTime.month)} ${entry.wallTime.year % 100}';

  String get _place => entry.place?.trim() ?? '';

  static String _month(int m) => const [
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
  ][m - 1];

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.read(context);
    final image = entry.media.where(isImage).firstOrNull;
    final file = image == null ? null : store.mediaFile(entry, image);
    Widget picture() {
      if (file == null) return const SizedBox.shrink();
      return Image.file(
        file,
        width: placed.image.width,
        height: placed.image.height,
        fit: BoxFit.contain,
        cacheWidth: 700,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    }

    Widget framed(Widget child) => entry.blend
        ? Padding(padding: const EdgeInsets.all(kMatSide), child: child)
        : DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(kMatSide),
              child: child,
            ),
          );

    Widget body;
    if (entry.blend && file != null) {
      body = FutureBuilder<Color?>(
        future: paperColorOf(file),
        builder: (context, snap) {
          final paper = snap.data;
          if (paper == null) return framed(picture());
          return framed(
            ColorFiltered(
              colorFilter: ColorFilter.matrix(blendMatrix(paper, kPaperColor)),
              child: picture(),
            ),
          );
        },
      );
    } else {
      body = framed(picture());
    }

    return Positioned(
      key: ValueKey(entry.id),
      left: placed.rect.left,
      top: placed.rect.top,
      width: placed.rect.width,
      height: placed.rect.height,
      child: InkWell(
        key: ValueKey('print-${entry.id}'),
        onTap: () => openEntry(context, entry.id),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            body,
            SizedBox(
              height: kCaptionHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_place.isNotEmpty)
                    Text(
                      _place,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: kInkBrown),
                    ),
                  Text(
                    _date,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 9, color: kInkBrown),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
