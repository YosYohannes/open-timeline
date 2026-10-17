import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../models/entry.dart';
import 'stamp_cutout.dart';

const kMatSide = 6.0;
const _cell = 5.0;
const _printGap = 2;
const _cutoutGap = 1;

class CollageItem {
  const CollageItem({
    required this.id,
    required this.ratio,
    required this.size,
    this.mask,
  });

  final String id;
  final double ratio;
  final String size;

  /// The stamp's outline when its paper is removed; a mounted print when null.
  final CutoutMask? mask;
}

class Placed {
  const Placed({required this.id, required this.rect, required this.image});

  final String id;

  /// The stamp with its mat, in page coordinates.
  final Rect rect;

  /// Just the image.
  final Size image;
}

double sizeFactor(String size) => switch (size) {
  sizeSmall => 0.7,
  sizeLarge => 1.5,
  _ => 1.0,
};

class _Shape {
  _Shape(this.item, this.image, this.mat);

  final CollageItem item;
  final Size image;
  final double mat;

  late final int cols = ((image.width + mat * 2) / _cell).ceil();
  late final int rows = ((image.height + mat * 2) / _cell).ceil();

  /// Offsets, in cells, of the cells the stamp covers.
  late final List<int> covered = () {
    final out = <int>[];
    final mask = item.mask;
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        if (mask == null || mask.at((x + 0.5) / cols, (y + 0.5) / rows)) {
          out.add(y * cols + x);
        }
      }
    }
    return out;
  }();

  int get gap => item.mask == null ? _printGap : _cutoutGap;
}

class _Page {
  _Page(this.cols, this.rows) : taken = Uint8List(cols * rows);

  final int cols;
  final int rows;
  final Uint8List taken;
  final placed = <Placed>[];

  bool fits(_Shape s, int x, int y) {
    for (final o in s.covered) {
      final cx = x + o % s.cols;
      final cy = y + o ~/ s.cols;
      if (taken[cy * cols + cx] != 0) return false;
    }
    return true;
  }

  (int, int)? find(_Shape s) {
    if (s.cols > cols || s.rows > rows) return null;
    for (var y = 0; y <= rows - s.rows; y++) {
      for (var x = 0; x <= cols - s.cols; x++) {
        if (fits(s, x, y)) return (x, y);
      }
    }
    return null;
  }

  void put(_Shape s, int x, int y) {
    final g = s.gap;
    for (final o in s.covered) {
      final cx = x + o % s.cols;
      final cy = y + o ~/ s.cols;
      for (var dy = -g; dy <= g; dy++) {
        for (var dx = -g; dx <= g; dx++) {
          final nx = cx + dx;
          final ny = cy + dy;
          if (nx >= 0 && ny >= 0 && nx < cols && ny < rows) {
            taken[ny * cols + nx] = 1;
          }
        }
      }
    }
    placed.add(
      Placed(
        id: s.item.id,
        rect: Rect.fromLTWH(
          x * _cell,
          y * _cell,
          s.image.width + s.mat * 2,
          s.image.height + s.mat * 2,
        ),
        image: s.image,
      ),
    );
  }
}

/// Packs stamps onto pages, each at the first free spot from the top left, so
/// outlines nest into each other instead of sitting in rows.
List<List<Placed>> layoutCollage(
  List<CollageItem> items,
  Size area, {
  double? baseHeight,
}) {
  if (items.isEmpty || area.width <= 0 || area.height <= 0) return const [];
  final base = baseHeight ?? math.min(area.width * 0.36, 150.0);
  final cols = (area.width / _cell).floor();
  final rows = (area.height / _cell).floor();

  _Shape shape(CollageItem it) {
    final mat = it.mask == null ? kMatSide : 0.0;
    final ratio = it.ratio.clamp(0.25, 4.0);
    var h = base * sizeFactor(it.size);
    var w = h * ratio;
    final maxW = cols * _cell - mat * 2 - _cell;
    if (w > maxW) {
      w = maxW;
      h = w / ratio;
    }
    final maxH = rows * _cell - mat * 2 - _cell;
    if (h > maxH) {
      h = maxH;
      w = h * ratio;
    }
    return _Shape(it, Size(w, h), mat);
  }

  final pages = <_Page>[];
  for (final it in items) {
    final s = shape(it);
    var spot = pages.isEmpty ? null : pages.last.find(s);
    if (spot == null) {
      pages.add(_Page(cols, rows));
      spot = pages.last.find(s) ?? (0, 0);
    }
    pages.last.put(s, spot.$1, spot.$2);
  }
  return [for (final p in pages) _centred(p.placed, area)];
}

List<Placed> _centred(List<Placed> placed, Size area) {
  var right = 0.0;
  var bottom = 0.0;
  for (final p in placed) {
    right = math.max(right, p.rect.right);
    bottom = math.max(bottom, p.rect.bottom);
  }
  final dx = math.max(0.0, (area.width - right) / 2);
  final dy = math.max(0.0, (area.height - bottom) / 2);
  return [
    for (final p in placed)
      Placed(id: p.id, rect: p.rect.shift(Offset(dx, dy)), image: p.image),
  ];
}
