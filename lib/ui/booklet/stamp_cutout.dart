import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'stamp_image.dart';
import 'subject_segmenter.dart';

const _maxSide = 700;
const _maskSide = 48;
const _paperNear = 24.0;
const _paperFar = 46.0;

class CutoutMask {
  const CutoutMask({
    required this.width,
    required this.height,
    required this.filled,
  });

  final int width;
  final int height;
  final Uint8List filled;

  bool at(double u, double v) {
    final x = (u * width).floor().clamp(0, width - 1);
    final y = (v * height).floor().clamp(0, height - 1);
    return filled[y * width + x] != 0;
  }
}

class Cutout {
  const Cutout({required this.file, required this.ratio, required this.mask});

  final File file;
  final double ratio;
  final CutoutMask mask;
}

class BackgroundRemoved {
  const BackgroundRemoved({
    required this.rgba,
    required this.width,
    required this.height,
  });

  final Uint8List rgba;
  final int width;
  final int height;
}

/// Makes the paper around a stamp transparent, or returns null when the paper
/// cannot be told apart from the stamp.
BackgroundRemoved? removeBackground(
  Uint8List rgba,
  int width,
  int height, {
  ui.Color? paperColor,
}) {
  final count = width * height;
  if (width < 4 || height < 4 || rgba.length < count * 4) return null;
  final paper = paperColor ?? estimatePaper(rgba, width, height);
  if (paper == null) return null;
  final pr = (paper.r * 255).round();
  final pg = (paper.g * 255).round();
  final pb = (paper.b * 255).round();

  final dist = Float32List(count);
  for (var i = 0; i < count; i++) {
    final dr = rgba[i * 4] - pr;
    final dg = rgba[i * 4 + 1] - pg;
    final db = rgba[i * 4 + 2] - pb;
    dist[i] = math.sqrt((dr * dr + dg * dg + db * db).toDouble());
  }

  final outside = Uint8List(count);
  final queue = Int32List(count);
  var head = 0;
  var tail = 0;
  void seed(int i) {
    if (outside[i] == 0 && dist[i] < _paperFar) {
      outside[i] = 1;
      queue[tail++] = i;
    }
  }

  for (var x = 0; x < width; x++) {
    seed(x);
    seed((height - 1) * width + x);
  }
  for (var y = 0; y < height; y++) {
    seed(y * width);
    seed(y * width + width - 1);
  }
  while (head < tail) {
    final i = queue[head++];
    final x = i % width;
    if (x > 0) seed(i - 1);
    if (x < width - 1) seed(i + 1);
    if (i >= width) seed(i - width);
    if (i < count - width) seed(i + width);
  }
  final removed = tail / count;
  if (removed < 0.01 || removed > 0.92) return null;

  final keep = _largestParts(outside, width, height);
  if (keep == null) return null;

  final alpha = Uint8List(count);
  var minX = width, minY = height, maxX = -1, maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = y * width + x;
      if (keep[i] == 0) continue;
      var a = 255.0;
      final nearOutside =
          (x > 0 && keep[i - 1] == 0) ||
          (x < width - 1 && keep[i + 1] == 0) ||
          (y > 0 && keep[i - width] == 0) ||
          (y < height - 1 && keep[i + width] == 0);
      if (nearOutside) {
        a =
            ((dist[i] - _paperNear) / (_paperFar - _paperNear)).clamp(
              0.0,
              1.0,
            ) *
            255;
      }
      alpha[i] = a.round();
      if (alpha[i] > 8) {
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
      }
    }
  }
  if (maxX < minX || maxY < minY) return null;

  final outW = maxX - minX + 1;
  final outH = maxY - minY + 1;
  final out = Uint8List(outW * outH * 4);
  for (var y = 0; y < outH; y++) {
    for (var x = 0; x < outW; x++) {
      final src = (y + minY) * width + (x + minX);
      final dst = (y * outW + x) * 4;
      out[dst] = rgba[src * 4];
      out[dst + 1] = rgba[src * 4 + 1];
      out[dst + 2] = rgba[src * 4 + 2];
      out[dst + 3] = alpha[src];
    }
  }
  return BackgroundRemoved(rgba: out, width: outW, height: outH);
}

/// Crops an image whose background is already transparent to what is left.
BackgroundRemoved? trimToSubject(Uint8List rgba, int width, int height) {
  if (width < 1 || height < 1 || rgba.length < width * height * 4) return null;
  var minX = width, minY = height, maxX = -1, maxY = -1;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (rgba[(y * width + x) * 4 + 3] <= 8) continue;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
  }
  if (maxX < minX || maxY < minY) return null;
  final outW = maxX - minX + 1;
  final outH = maxY - minY + 1;
  if (outW * outH * 20 < width * height) return null;
  final out = Uint8List(outW * outH * 4);
  for (var y = 0; y < outH; y++) {
    final from = ((y + minY) * width + minX) * 4;
    out.setRange(y * outW * 4, (y + 1) * outW * 4, rgba, from);
  }
  return BackgroundRemoved(rgba: out, width: outW, height: outH);
}

/// Marks the stamp itself: its biggest connected piece and any piece at least
/// a twentieth of that size, so dust and scanner specks are dropped.
Uint8List? _largestParts(Uint8List outside, int width, int height) {
  final count = width * height;
  final label = Int32List(count);
  final queue = Int32List(count);
  final sizes = <int>[0];
  for (var start = 0; start < count; start++) {
    if (outside[start] != 0 || label[start] != 0) continue;
    final id = sizes.length;
    var head = 0;
    var tail = 0;
    label[start] = id;
    queue[tail++] = start;
    while (head < tail) {
      final i = queue[head++];
      final x = i % width;
      void visit(int j) {
        if (outside[j] == 0 && label[j] == 0) {
          label[j] = id;
          queue[tail++] = j;
        }
      }

      if (x > 0) visit(i - 1);
      if (x < width - 1) visit(i + 1);
      if (i >= width) visit(i - width);
      if (i < count - width) visit(i + width);
    }
    sizes.add(tail);
  }
  if (sizes.length == 1) return null;
  final biggest = sizes.reduce(math.max);
  final keepId = {
    for (var id = 1; id < sizes.length; id++)
      if (sizes[id] * 20 >= biggest) id,
  };
  final keep = Uint8List(count);
  for (var i = 0; i < count; i++) {
    if (keepId.contains(label[i])) keep[i] = 1;
  }
  return keep;
}

CutoutMask maskOf(Uint8List rgba, int width, int height) {
  final scale = _maskSide / math.max(width, height);
  final mw = math.max(1, (width * scale).round());
  final mh = math.max(1, (height * scale).round());
  final filled = Uint8List(mw * mh);
  for (var my = 0; my < mh; my++) {
    final y0 = (my * height / mh).floor();
    final y1 = math.max(y0 + 1, ((my + 1) * height / mh).ceil());
    for (var mx = 0; mx < mw; mx++) {
      final x0 = (mx * width / mw).floor();
      final x1 = math.max(x0 + 1, ((mx + 1) * width / mw).ceil());
      var solid = 0;
      var total = 0;
      for (var y = y0; y < math.min(y1, height); y++) {
        for (var x = x0; x < math.min(x1, width); x++) {
          total++;
          if (rgba[(y * width + x) * 4 + 3] >= 128) solid++;
        }
      }
      filled[my * mw + mx] = total > 0 && solid * 3 >= total ? 1 : 0;
    }
  }
  return CutoutMask(width: mw, height: mh, filled: filled);
}

class _Job {
  const _Job(this.rgba, this.width, this.height, this.paper, this.subject);

  final Uint8List rgba;
  final int width;
  final int height;
  final int? paper;
  final bool subject;
}

({Uint8List rgba, int width, int height, CutoutMask mask})? _run(_Job job) {
  final r = job.subject
      ? trimToSubject(job.rgba, job.width, job.height)
      : removeBackground(
          job.rgba,
          job.width,
          job.height,
          paperColor: job.paper == null ? null : ui.Color(job.paper!),
        );
  if (r == null) return null;
  return (
    rgba: r.rgba,
    width: r.width,
    height: r.height,
    mask: maskOf(r.rgba, r.width, r.height),
  );
}

Directory get _cacheDir => Directory('${Directory.systemTemp.path}/cutouts');

final _results = <String, Cutout?>{};
final _pending = <String, Future<Cutout?>>{};
final _waiting = <Completer<void>>[];
var _running = 0;

const cutoutSubject = 'subject';

Cutout? cachedCutout(File file, [String method = '']) =>
    _results[_key(file, method)];

bool hasCutout(File file, [String method = '']) =>
    _results.containsKey(_key(file, method));

ui.Color? paperOfMethod(String method) {
  final m = RegExp(r'^#([0-9A-Fa-f]{6})$').firstMatch(method);
  return m == null ? null : ui.Color(0xFF000000 | int.parse(m[1]!, radix: 16));
}

String _key(File file, String method) {
  final name = file.uri.pathSegments.last;
  final tag = method.isEmpty ? 'auto' : method.replaceAll('#', 'c');
  return '$name-${file.lengthSync()}-$tag';
}

Future<void> _slot() async {
  if (_running < 3) {
    _running++;
    return;
  }
  final c = Completer<void>();
  _waiting.add(c);
  await c.future;
}

void _release() {
  if (_waiting.isNotEmpty) {
    _waiting.removeAt(0).complete();
  } else {
    _running--;
  }
}

/// The stamp with its paper removed, kept as a PNG in the cache folder, or
/// null when the paper cannot be removed.
Future<Cutout?> cutoutOf(File file, [String method = '']) {
  final key = _key(file, method);
  if (_results.containsKey(key)) return Future.value(_results[key]);
  return _pending.putIfAbsent(key, () async {
    await _slot();
    try {
      final c = await _make(file, key, method);
      _results[key] = c;
      return c;
    } catch (_) {
      _results[key] = null;
      return null;
    } finally {
      _release();
      _pending.remove(key);
    }
  });
}

Future<Cutout?> _make(File file, String key, String method) async {
  final png = File('${_cacheDir.path}/$key.png');
  final maskFile = File('${_cacheDir.path}/$key.mask');
  final none = File('${_cacheDir.path}/$key.none');
  if (none.existsSync()) return null;
  if (png.existsSync() && maskFile.existsSync()) {
    final bytes = maskFile.readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    final mw = data.getUint16(0);
    final mh = data.getUint16(2);
    final ratio = data.getFloat32(4);
    return Cutout(
      file: png,
      ratio: ratio,
      mask: CutoutMask(
        width: mw,
        height: mh,
        filled: Uint8List.sublistView(bytes, 8),
      ),
    );
  }

  final subject = method == cutoutSubject;
  final source = subject ? await subjectSegmenter.segment(file) : file;
  if (source == null) return null;
  final codec = await ui.instantiateImageCodec(
    await source.readAsBytes(),
    targetWidth: _maxSide,
  );
  final frame = await codec.getNextFrame();
  final w = frame.image.width;
  final h = frame.image.height;
  final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
  frame.image.dispose();
  codec.dispose();
  if (data == null) return null;
  final paper = paperOfMethod(method);
  final result = await compute(
    _run,
    _Job(data.buffer.asUint8List(), w, h, paper?.toARGB32(), subject),
  );
  _cacheDir.createSync(recursive: true);
  if (result == null) {
    none.writeAsBytesSync(const []);
    return null;
  }
  final done = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    result.rgba,
    result.width,
    result.height,
    ui.PixelFormat.rgba8888,
    done.complete,
  );
  final image = await done.future;
  final encoded = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  if (encoded == null) return null;
  final ratio = result.width / result.height;
  final header = ByteData(8)
    ..setUint16(0, result.mask.width)
    ..setUint16(2, result.mask.height)
    ..setFloat32(4, ratio);
  png.writeAsBytesSync(encoded.buffer.asUint8List());
  maskFile.writeAsBytesSync([
    ...header.buffer.asUint8List(),
    ...result.mask.filled,
  ]);
  return Cutout(file: png, ratio: ratio, mask: result.mask);
}
