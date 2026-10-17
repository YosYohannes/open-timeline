import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

const kPaperColor = ui.Color(0xFFF3ECDD);

ui.Size? pngSize(Uint8List head) {
  if (head.length < 24) return null;
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < signature.length; i++) {
    if (head[i] != signature[i]) return null;
  }
  final data = ByteData.sublistView(head);
  final w = data.getUint32(16);
  final h = data.getUint32(20);
  if (w == 0 || h == 0) return null;
  return ui.Size(w.toDouble(), h.toDouble());
}

final _ratios = <String, double>{};

double aspectRatioOf(File file) {
  return _ratios.putIfAbsent(file.path, () {
    try {
      final raf = file.openSync();
      try {
        final size = pngSize(raf.readSync(24));
        return size == null ? 1.0 : size.width / size.height;
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return 1.0;
    }
  });
}

ui.Color? estimatePaper(Uint8List rgba, int width, int height) {
  if (width < 1 || height < 1 || rgba.length < width * height * 4) return null;
  final ring = math.max(1, (math.min(width, height) * 0.06).round());
  final hist = List.generate(3, (_) => List.filled(256, 0));
  var n = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final edge =
          x < ring || y < ring || x >= width - ring || y >= height - ring;
      if (!edge) continue;
      final i = (y * width + x) * 4;
      if (rgba[i + 3] < 128) continue;
      for (var c = 0; c < 3; c++) {
        hist[c][rgba[i + c]]++;
      }
      n++;
    }
  }
  if (n == 0) return null;
  int median(List<int> h) {
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += h[v];
      if (seen * 2 >= n) return v;
    }
    return 255;
  }

  return ui.Color.fromARGB(
    255,
    median(hist[0]),
    median(hist[1]),
    median(hist[2]),
  );
}

bool isLightPaper(ui.Color c) {
  final r = (c.r * 255).round();
  final g = (c.g * 255).round();
  final b = (c.b * 255).round();
  final lo = math.min(r, math.min(g, b));
  final hi = math.max(r, math.max(g, b));
  return lo >= 185 && hi - lo <= 75;
}

final _papers = <String, Future<ui.Color?>>{};

Future<ui.Color?> paperColorOf(File file) {
  final key = '${file.path}:${file.lengthSync()}';
  return _papers.putIfAbsent(key, () async {
    try {
      final codec = await ui.instantiateImageCodec(
        await file.readAsBytes(),
        targetWidth: 64,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (data == null) return null;
      return estimatePaper(data.buffer.asUint8List(), w, h);
    } catch (_) {
      return null;
    }
  });
}
