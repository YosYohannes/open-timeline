import 'dart:math' as math;
import 'dart:ui';

import '../../models/entry.dart';

const kMatSide = 6.0;
const kCaptionHeight = 22.0;

class CollageItem {
  const CollageItem({
    required this.id,
    required this.ratio,
    required this.size,
  });

  final String id;
  final double ratio;
  final String size;
}

class Placed {
  const Placed({required this.id, required this.rect, required this.image});

  final String id;

  /// Mat, image and caption together, in page coordinates.
  final Rect rect;

  /// Just the image.
  final Size image;
}

double sizeFactor(String size) => switch (size) {
  sizeSmall => 0.7,
  sizeLarge => 1.5,
  _ => 1.0,
};

class _Cell {
  _Cell(this.item, this.w, this.h);

  final CollageItem item;
  double w;
  double h;
}

List<List<Placed>> layoutCollage(
  List<CollageItem> items,
  Size area, {
  double gap = 14,
  double? baseHeight,
}) {
  if (items.isEmpty || area.width <= 0 || area.height <= 0) return const [];
  final base = baseHeight ?? math.min(area.width * 0.36, 150.0);
  final extraW = kMatSide * 2;
  final extraH = kMatSide * 2 + kCaptionHeight;

  _Cell cell(CollageItem it) {
    final ratio = it.ratio.clamp(0.25, 4.0);
    var h = base * sizeFactor(it.size);
    var w = h * ratio;
    final maxW = area.width - extraW;
    if (w > maxW) {
      w = maxW;
      h = w / ratio;
    }
    final maxH = area.height - extraH;
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
    return _Cell(it, w, h);
  }

  final rows = <List<_Cell>>[];
  var row = <_Cell>[];
  var rowWidth = 0.0;
  for (final it in items) {
    final c = cell(it);
    final next = (row.isEmpty ? 0.0 : gap) + c.w + extraW;
    if (row.isNotEmpty && rowWidth + next > area.width) {
      rows.add(row);
      row = [];
      rowWidth = 0;
    }
    row.add(c);
    rowWidth += (row.length == 1 ? 0.0 : gap) + c.w + extraW;
  }
  if (row.isNotEmpty) rows.add(row);

  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    final last = i == rows.length - 1;
    final images = r.fold(0.0, (n, c) => n + c.w);
    final fixed = (r.length - 1) * gap + r.length * extraW;
    var scale = (area.width - fixed) / images;
    scale = last ? math.min(scale, 1.0) : math.min(scale, 1.35);
    scale = math.max(scale, 0.5);
    for (final c in r) {
      c.w *= scale;
      c.h *= scale;
    }
  }

  final pages = <List<Placed>>[];
  var placed = <Placed>[];
  var y = 0.0;
  for (final r in rows) {
    final rowHeight = r.map((c) => c.h + extraH).reduce(math.max);
    if (placed.isNotEmpty && y + rowHeight > area.height) {
      pages.add(placed);
      placed = [];
      y = 0;
    }
    final rowWidth =
        r.fold(0.0, (n, c) => n + c.w + extraW) + (r.length - 1) * gap;
    var x = (area.width - rowWidth) / 2;
    for (final c in r) {
      final h = c.h + extraH;
      placed.add(
        Placed(
          id: c.item.id,
          rect: Rect.fromLTWH(x, y + (rowHeight - h) / 2, c.w + extraW, h),
          image: Size(c.w, c.h),
        ),
      );
      x += c.w + extraW + gap;
    }
    y += rowHeight + gap;
  }
  if (placed.isNotEmpty) pages.add(placed);
  return pages;
}
