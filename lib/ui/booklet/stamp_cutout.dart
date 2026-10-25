import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'subject_segmenter.dart';

const _maxSide = 700;
const _maskSide = 48;

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
  const _Job(this.rgba, this.width, this.height);

  final Uint8List rgba;
  final int width;
  final int height;
}

({Uint8List rgba, int width, int height, CutoutMask mask})? _run(_Job job) {
  final r = trimToSubject(job.rgba, job.width, job.height);
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

Cutout? cachedCutout(File file) => _results[_key(file)];

bool hasCutout(File file) => _results.containsKey(_key(file));

String _key(File file) {
  final name = file.uri.pathSegments.last;
  return '$name-${file.lengthSync()}-subject';
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

/// The stamp cut out of its picture by the phone's on-device AI, kept as a PNG
/// in the cache folder, or null when no item was found. A failure of the AI
/// itself, such as a model that is still downloading, is not remembered.
Future<Cutout?> cutoutOf(File file) {
  final key = _key(file);
  if (_results.containsKey(key)) return Future.value(_results[key]);
  return _pending.putIfAbsent(key, () async {
    await _slot();
    try {
      final c = await _make(file, key);
      if (c != null || subjectSegmenter.lastError == null) _results[key] = c;
      return c;
    } catch (_) {
      return null;
    } finally {
      _release();
      _pending.remove(key);
    }
  });
}

Future<Cutout?> _make(File file, String key) async {
  final png = File('${_cacheDir.path}/$key.png');
  final maskFile = File('${_cacheDir.path}/$key.mask');
  final none = File('${_cacheDir.path}/$key.none');
  if (none.existsSync()) return null;
  if (png.existsSync() && maskFile.existsSync()) {
    final bytes = maskFile.readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    return Cutout(
      file: png,
      ratio: data.getFloat32(4),
      mask: CutoutMask(
        width: data.getUint16(0),
        height: data.getUint16(2),
        filled: Uint8List.sublistView(bytes, 8),
      ),
    );
  }

  final source = await subjectSegmenter.segment(file);
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
  final result = await compute(_run, _Job(data.buffer.asUint8List(), w, h));
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
